require "cases/helper"
require 'models/post'
require 'models/comment'
require 'models/author'
require 'models/rating'

module ActiveRecord
  class RelationTest < ActiveRecord::TestCase
    fixtures :posts, :comments, :authors

    class FakeKlass < Struct.new(:table_name, :name)
      extend ActiveRecord::Delegation::DelegateCache

      inherited self

      def self.connection
        Post.connection
      end

      def self.table_name
        'fake_table'
      end
    end

    def test_construction
      relation = Relation.new FakeKlass, :b
      assert_equal FakeKlass, relation.klass
      assert_equal :b, relation.table
      assert !relation.loaded, 'relation is not loaded'
    end

    def test_responds_to_model_and_returns_klass
      relation = Relation.new FakeKlass, :b
      assert_equal FakeKlass, relation.model
    end

    def test_initialize_single_values
      relation = Relation.new FakeKlass, :b
      (Relation::SINGLE_VALUE_METHODS - [:create_with]).each do |method|
        assert_nil relation.send("#{method}_value"), method.to_s
      end
      assert_equal({}, relation.create_with_value)
    end

    def test_multi_value_initialize
      relation = Relation.new FakeKlass, :b
      Relation::MULTI_VALUE_METHODS.each do |method|
        assert_equal [], relation.send("#{method}_values"), method.to_s
      end
    end

    def test_extensions
      relation = Relation.new FakeKlass, :b
      assert_equal [], relation.extensions
    end

    def test_empty_where_values_hash
      relation = Relation.new FakeKlass, :b
      assert_equal({}, relation.where_values_hash)

      relation.where! :hello
      assert_equal({}, relation.where_values_hash)
    end

    def test_has_values
      relation = Relation.new Post, Post.arel_table
      relation.where! relation.table[:id].eq(10)
      assert_equal({:id => 10}, relation.where_values_hash)
    end

    def test_values_wrong_table
      relation = Relation.new Post, Post.arel_table
      relation.where! Comment.arel_table[:id].eq(10)
      assert_equal({}, relation.where_values_hash)
    end

    def test_tree_is_not_traversed
      relation = Relation.new Post, Post.arel_table
      left     = relation.table[:id].eq(10)
      right    = relation.table[:id].eq(10)
      combine  = left.and right
      relation.where! combine
      assert_equal({}, relation.where_values_hash)
    end

    def test_table_name_delegates_to_klass
      relation = Relation.new FakeKlass.new('posts'), :b
      assert_equal 'posts', relation.table_name
    end

    def test_scope_for_create
      relation = Relation.new FakeKlass, :b
      assert_equal({}, relation.scope_for_create)
    end

    def test_create_with_value
      relation = Relation.new Post, Post.arel_table
      hash = { :hello => 'world' }
      relation.create_with_value = hash
      assert_equal hash, relation.scope_for_create
    end

    def test_create_with_value_with_wheres
      relation = Relation.new Post, Post.arel_table
      relation.where! relation.table[:id].eq(10)
      relation.create_with_value = {:hello => 'world'}
      assert_equal({:hello => 'world', :id => 10}, relation.scope_for_create)
    end

    # FIXME: is this really wanted or expected behavior?
    def test_scope_for_create_is_cached
      relation = Relation.new Post, Post.arel_table
      assert_equal({}, relation.scope_for_create)

      relation.where! relation.table[:id].eq(10)
      assert_equal({}, relation.scope_for_create)

      relation.create_with_value = {:hello => 'world'}
      assert_equal({}, relation.scope_for_create)
    end

    def test_bad_constants_raise_errors
      assert_raises(NameError) do
        ActiveRecord::Relation::HelloWorld
      end
    end

    def test_empty_eager_loading?
      relation = Relation.new FakeKlass, :b
      assert !relation.eager_loading?
    end

    def test_eager_load_values
      relation = Relation.new FakeKlass, :b
      relation.eager_load! :b
      assert relation.eager_loading?
    end

    def test_references_values
      relation = Relation.new FakeKlass, :b
      assert_equal [], relation.references_values
      relation = relation.references(:foo).references(:omg, :lol)
      assert_equal ['foo', 'omg', 'lol'], relation.references_values
    end

    def test_references_values_dont_duplicate
      relation = Relation.new FakeKlass, :b
      relation = relation.references(:foo).references(:foo)
      assert_equal ['foo'], relation.references_values
    end

    test 'merging a hash into a relation' do
      relation = Relation.new FakeKlass, :b
      relation = relation.merge where: :lol, readonly: true

      assert_equal [:lol], relation.where_values
      assert_equal true, relation.readonly_value
    end

    test 'merging an empty hash into a relation' do
      assert_equal [], Relation.new(FakeKlass, :b).merge({}).where_values
    end

    test 'merging a hash with unknown keys raises' do
      assert_raises(ArgumentError) { Relation::HashMerger.new(nil, omg: 'lol') }
    end

    test '#values returns a dup of the values' do
      relation = Relation.new(FakeKlass, :b).where! :foo
      values   = relation.values

      values[:where] = nil
      assert_not_nil relation.where_values
    end

    test 'relations can be created with a values hash' do
      relation = Relation.new(FakeKlass, :b, where: [:foo])
      assert_equal [:foo], relation.where_values
    end

    test 'merging a single where value' do
      relation = Relation.new(FakeKlass, :b)
      relation.merge!(where: :foo)
      assert_equal [:foo], relation.where_values
    end

    test 'merging a hash interpolates conditions' do
      klass = Class.new(FakeKlass) do
        def self.sanitize_sql(args)
          raise unless args == ['foo = ?', 'bar']
          'foo = bar'
        end
      end

      relation = Relation.new(klass, :b)
      relation.merge!(where: ['foo = ?', 'bar'])
      assert_equal ['foo = bar'], relation.where_values
    end

    def test_merging_readonly_false
      relation = Relation.new FakeKlass, :b
      readonly_false_relation = relation.readonly(false)
      # test merging in both directions
      assert_equal false, relation.merge(readonly_false_relation).readonly_value
      assert_equal false, readonly_false_relation.merge(relation).readonly_value
    end

    def test_relation_merging_with_merged_joins_as_symbols
      special_comments_with_ratings = SpecialComment.joins(:ratings)
      posts_with_special_comments_with_ratings = Post.group("posts.id").joins(:special_comments).merge(special_comments_with_ratings)
      assert_equal 3, authors(:david).posts.merge(posts_with_special_comments_with_ratings).count.length
    end

    def test_conflicting_bind_values
      assert_nothing_raised do
        CommentWithConflictingDefaultScope.joins(:post_with_conflicting_default_scope).delete_all
      end
    end

    def test_relation_merging_with_joins_as_join_dependency_pick_proper_parent
      post = Post.create!(title: "haha", body: "huhu")
      comment = post.comments.create!(body: "hu")
      3.times { comment.ratings.create! }

      relation = Post.joins(:comments).merge Comment.joins(:ratings)

      assert_equal 3, relation.where(id: post.id).pluck(:id).size
    end

    def test_respond_to_for_non_selected_element
      post = Post.select(:title).first
      assert_equal false, post.respond_to?(:body), "post should not respond_to?(:body) since invoking it raises exception"

      silence_warnings { post = Post.select("'title' as post_title").first }
      assert_equal false, post.respond_to?(:title), "post should not respond_to?(:body) since invoking it raises exception"
    end

    def test_select_quotes_when_using_from_clause
      skip_if_sqlite3_version_includes_quoting_bug
      quoted_join = ActiveRecord::Base.connection.quote_table_name("join")
      selected = Post.select(:join).from(Post.select("id as #{quoted_join}")).map(&:join)
      assert_equal Post.pluck(:id), selected
    end

    def test_selecting_aliased_attribute_quotes_column_name_when_from_is_used
      skip_if_sqlite3_version_includes_quoting_bug
      klass = Class.new(ActiveRecord::Base) do
        self.table_name = :test_with_keyword_column_name
        alias_attribute :description, :desc
      end
      klass.create!(description: "foo")

      assert_equal ["foo"], klass.select(:description).from(klass.all).map(&:desc)
    end

    def test_relation_merging_with_merged_joins_as_strings
      join_string = "LEFT OUTER JOIN #{Rating.quoted_table_name} ON #{SpecialComment.quoted_table_name}.id = #{Rating.quoted_table_name}.comment_id"
      special_comments_with_ratings = SpecialComment.joins join_string
      posts_with_special_comments_with_ratings = Post.group("posts.id").joins(:special_comments).merge(special_comments_with_ratings)
      assert_equal 3, authors(:david).posts.merge(posts_with_special_comments_with_ratings).count.length
    end

    class EnsureRoundTripTypeCasting < ActiveRecord::Type::Value
      def type
        :string
      end

      def type_cast_from_database(value)
        raise value unless value == "type cast for database"
        "type cast from database"
      end

      def type_cast_for_database(value)
        raise value unless value == "value from user"
        "type cast for database"
      end
    end

    class UpdateAllTestModel < ActiveRecord::Base
      self.table_name = 'posts'

      attribute :body, EnsureRoundTripTypeCasting.new
    end

    def test_update_all_goes_through_normal_type_casting
      UpdateAllTestModel.update_all(body: "value from user", type: nil) # No STI

      assert_equal "type cast from database", UpdateAllTestModel.first.body
    end

    private

    def skip_if_sqlite3_version_includes_quoting_bug
      if sqlite3_version_includes_quoting_bug?
        skip <<-ERROR.squish
          You are using an outdated version of SQLite3 which has a bug in
          quoted column names. Please update SQLite3 and rebuild the sqlite3
          ruby gem
        ERROR
      end
    end

    def sqlite3_version_includes_quoting_bug?
      if current_adapter?(:SQLite3Adapter)
        selected_quoted_column_names = ActiveRecord::Base.connection.exec_query(
          'SELECT "join" FROM (SELECT id AS "join" FROM posts) subquery'
        ).columns
        ["join"] != selected_quoted_column_names
      end
    end
  end
end
