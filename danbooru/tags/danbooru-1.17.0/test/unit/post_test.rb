require File.dirname(__FILE__) + '/../test_helper'

class PostTest < ActiveSupport::TestCase
  fixtures :users, :posts, :table_data
  
  def setup
    MEMCACHE.flush_all

    @test_number = 1
    
    # TODO: revert these after testing in teardown
    CONFIG["image_samples"] = true
    CONFIG["sample_width"] = 100
    CONFIG["sample_height"] = 100
    CONFIG["sample_ratio"] = 1.25
  end
  
  def search_posts(tags, options = {})
    Post.find_by_sql(Post.generate_sql(tags, options)).sort {|a, b| a.id <=> b.id}
  end
    
  def test_api
    post = create_post("tag1 tag2")
    assert_nothing_raised {post.to_json}
    assert_nothing_raised {post.to_xml}
  end
  
  def test_cache
    cache_version = Cache.get("$cache_version").to_i
    tag1_version = Cache.get("tag:tag1").to_i
    tag2_version = Cache.get("tag:tag2").to_i
    create_post("tag1 tag2")
    assert_greater(Cache.get("$cache_version").to_i, cache_version)
    assert_greater(Cache.get("tag:tag1").to_i, tag1_version)
    assert_greater(Cache.get("tag:tag2").to_i, tag2_version)
  end
  
  def test_change_sequence
    post = create_post("tag1 tag2")
    first_change_seq = post.change_seq
    update_post(post, :tags => "tag3 tag4")
    assert_equal(first_change_seq + 1, post.change_seq)
    
    # TODO: add tests to make sure change_seq is updated when status or tags are
    # changed.
  end
  
  def test_comments
    post = create_post("tag1 tag2")
    assert_equal(0, post.comments.size)
    assert_equal(0, post.recent_comments.size)
    
    comment1 = create_comment(post, :body => "comment 1")
    assert_equal(1, post.comments.size)
    assert_equal(1, post.recent_comments.size)
    
    comment2 = create_comment(post, :body => "comment 2")
    assert_equal(2, post.comments.size)
    assert_equal(2, post.recent_comments.size)
    assert_equal("comment 1", post.comments[0].body)
    assert_equal("comment 2", post.comments[1].body)
    
    comment3 = create_comment(post, :body => "comment 3")
    comment4 = create_comment(post, :body => "comment 4")
    comment5 = create_comment(post, :body => "comment 5")
    comment6 = create_comment(post, :body => "comment 6")
    comment7 = create_comment(post, :body => "comment 7")
    assert_equal(7, post.comments.size)
    assert_equal(6, post.recent_comments.size)
    assert_equal("comment 2", post.recent_comments[0].body)
  end
  
  def test_count
    # Includes posts from fixtures
    
    assert_equal(5, Post.fast_count)
    assert_equal(0, Post.fast_count("tag1"))
    assert_equal(0, Post.fast_count("tag2"))
    
    post1 = create_post("tag1", :file => upload_jpeg("#{RAILS_ROOT}/test/mocks/test/test1.jpg"))
    assert_equal(6, Post.fast_count)
    assert_equal(1, Post.fast_count("tag1"))
    assert_equal(0, Post.fast_count("tag2"))
    
    post2 = create_post("tag2", :file => upload_jpeg("#{RAILS_ROOT}/test/mocks/test/test2.jpg"))
    assert_equal(7, Post.fast_count)
    assert_equal(1, Post.fast_count("tag1"))
    assert_equal(1, Post.fast_count("tag2"))
    
    post3 = create_post("tag2 tag3", :file => upload_jpeg("#{RAILS_ROOT}/test/mocks/test/test3.jpg"))
    assert_equal(8, Post.fast_count)
    assert_equal(1, Post.fast_count("tag1"))
    assert_equal(2, Post.fast_count("tag2"))

    post4 = create_post("tag2 tag3", :file => upload_jpeg("#{RAILS_ROOT}/test/mocks/test/test4.jpg"), :status => "deleted")
    assert_equal(1, Post.fast_deleted_count)
    assert_equal(0, Post.fast_deleted_count("tag1"))
    assert_equal(1, Post.fast_deleted_count("tag2"))
    
    # These tests currently fail. This is because a deleted post won't decrement the tag's post count
    # until the post is deleted from the database (which then activates the database triggers which correct
    # the post counts).
    # post3.destroy
    # assert_equal(8, Post.count) # Post isn't actually deleted from database, just set status = deleted
    # assert_equal(7, Post.fast_count)
    # assert_equal(1, Post.fast_count("tag1"))
    # assert_equal(1, Post.fast_count("tag2"))
    # 
    # post2.destroy
    # assert_equal(8, Post.count)
    # assert_equal(6, Post.fast_count)
    # assert_equal(1, Post.fast_count("tag1"))
    # assert_equal(0, Post.fast_count("tag2"))
    # 
    # post1.destroy
    # assert_equal(8, Post.count)
    # assert_equal(5, Post.fast_count)
    # assert_equal(0, Post.fast_count("tag1"))
    # assert_equal(0, Post.fast_count("tag2"))
  end
  
  def test_cgi_upload
    post = create_post("tag1")
    assert(File.exists?(post.file_path), "File not found")
    assert(File.exists?(post.preview_path), "Preview not found")
    assert(File.exists?(post.sample_path), "Sample not found")
    assert_not_equal(0, File.size(post.file_path))
    assert_not_equal(0, File.size(post.preview_path))
    assert_not_equal(0, File.size(post.sample_path))
    assert_equal("fa033b0f3f0bb536770bbd5580575aac", post.md5)
  end
  
  def test_download_from_source
    post = create_post("tag1", :file => nil, :source => "http://www.google.com/intl/en_ALL/images/logo.gif")
    assert(File.exists?(post.file_path), "File not found")
    assert(File.exists?(post.preview_path), "Preview not found")
    assert_not_equal(0, File.size(post.file_path))
    assert_not_equal(0, File.size(post.preview_path))
    assert_equal("e80d1c59a673f560785784fb1ac10959", post.md5)
  end
  
  def test_uniqueness
    original_count = Post.count
    create_post("tag1", :file => upload_jpeg("#{RAILS_ROOT}/test/mocks/test/test2.jpg"))
    assert_equal(original_count + 1, Post.count)
    post = create_post("tag1", :file => upload_jpeg("#{RAILS_ROOT}/test/mocks/test/test2.jpg"))
    assert(post.errors.invalid?(:md5), "No error raised on duplicate MD5")
    assert_equal(original_count + 1, Post.count)
  end
  
  def test_non_image_upload
    post = create_post("tag1 tag2", :file => nil, :tags => "tag1", :source => "http://www.google.com/index.html")
    assert(post.errors.invalid?(:file), "Invalid content type was not rejected")
  end
  
  def test_parents
    # Test for nonexistent parent
    post = create_post("tag1", :parent_id => 1_000_000)
    assert(post.errors.invalid?(:parent_id), "Parent not validated")
    
    # Test to see if the has_children field is updated correctly
    p1 = create_post("tag1 tag2")
    assert(!p1.has_children?, "Parent should not have any children")
    c1 = create_post("tag1 tag2", :parent_id => p1.id)
    p1.reload
    assert(p1.has_children?, "Parent not updated after child was added")
    
    # Test to make sure favorites are assigned to a parent when a post is deleted
    c2 = create_post("tag1 tag2", :parent_id => p1.id)
    Favorite.create(:post_id => c2.id, :user_id => 1)
    c2.destroy
    p1.reload
    assert_nil(Favorite.find(:first, :conditions => ["post_id = ? AND user_id = ?", c2.id, 1]))
    assert_not_nil(Favorite.find(:first, :conditions => ["post_id = ? AND user_id =?", p1.id, 1]))
    assert(p1.has_children?, "Parent should still have children")
    
    # Test to make sure has_children is updated when post is updated
    p2 = create_post("tag1 tag2")
    update_post(c1, :parent_id => p2.id)
    p1.reload
    p2.reload
    assert(!p1.has_children?, "Parent should no longer have children")
    assert(p2.has_children?, "Parent should have children")
    
    # Parent should be updated when all children are deleted
    c1.delete!
    p2.reload
    assert(!p2.has_children?, "Parent should not have children")

    # Undeleting should restore the status
    c1.undelete!
    p2.reload
    assert(p2.has_children?, "Parent should have children")
  end
  
  def test_rating
    post = create_post("tag1 tag2")
    post.rating = "explicit"
    post.save
    post.reload
    assert_equal("e", post.rating)
    assert_equal("Explicit", post.pretty_rating)
    
    # Test invalid rating
    post.rating = "gohigohifdg"
    post.save
    post.reload
    assert_equal("q", post.rating)
  end

  def test_delete
    post = create_post("tag1 tag2")
    post.delete!
    assert_not_nil(Post.find_by_id(post.id))
    post.reload
    assert_equal("deleted", post.status)
  end
  
  def test_update_cached_tags
    p = create_post("moge chichi")
    assert_equal("chichi moge", p.cached_tags)
    t = Tag.find_by_name("chichi")
    t.update_attribute(:name, "oppai")
    Post.recalculate_cached_tags(p.id)
    p.reload
    assert_equal("moge oppai", p.cached_tags)
  end
 
  def test_tag_merging_a
    post = create_post("tag1 tag2")
    p1 = Post.find(post.id)
    update_post(p1, :tags => "tag1 tag2 tag-a", :old_tags => "tag1 tag2")
    p2 = Post.find(post.id)
    update_post(p2, :tags => "tag1 tag2 tag-b", :old_tags => "tag1 tag2")
    post.reload
    assert_equal("tag-a tag-b tag1 tag2", post.cached_tags)
  end

  def test_tag_merging_b
    post = create_post("tag1 tag2")
    p1 = Post.find(post.id)
    update_post(p1, :tags => "tag1", :old_tags => "tag1 tag2")
    p2 = Post.find(post.id)
    update_post(p2, :tags => "tag1 tag2 tag-a", :old_tags => "tag1 tag2")
    post.reload
    assert_equal("tag-a tag1", post.cached_tags)
  end

  def test_tag_merging_c
    post = create_post("tag1 tag2 tag3")
    p1 = Post.find(post.id)
    update_post(p1, :tags => "tag1 tag2", :old_tags => "tag1 tag2 tag3")
    p2 = Post.find(post.id)
    update_post(p2, :tags => "tag1 tag3", :old_tags => "tag1 tag2 tag3")
    post.reload
    assert_equal("tag1", post.cached_tags)
  end
  
  def test_tag_aliases
    tag_z = Tag.new(:name => "tag-z")
    tag_z.cached_related_expires_on = 1.year.from_now
    tag_z.save
    TagAlias.create(:name => "tag-x", :alias_id => tag_z.id, :is_pending => false, :reason => "none", :creator_id => 1)
    post = create_post("tag-x")
    post.reload
    assert_equal("tag-z", post.cached_tags)
  end
  
  def test_tag_implications
    tag_a = Tag.new(:name => "tag-a")
    tag_a.cached_related_expires_on = 1.year.from_now
    tag_a.save
    tag_b = Tag.new(:name => "tag-b")
    tag_b.cached_related_expires_on = 1.year.from_now
    tag_b.save
    TagImplication.create(:predicate_id => tag_a.id, :consequent_id => tag_b.id, :is_pending => false)
    post = create_post("tag-a")
    post.reload
    assert_equal("tag-a tag-b", post.cached_tags)
  end
  
  def test_tag_history
    post = create_post("tag-a")
    assert_equal("tag-a", post.tag_history[0].tags)
    assert_equal(1, post.tag_history.size)
    
    update_post(post, :tags => "tag-b")
    post.reload
    assert_equal("tag-b", post.tag_history[0].tags)
    assert_equal(2, post.tag_history.size)
    
    update_post(post, :tags => "tag-c")
    post.reload
    assert_equal("tag-c", post.tag_history[0].tags)
    assert_equal(3, post.tag_history.size)
  end
  
  def test_metatags
    post = create_post("tag1 tag2")
    
    # Test creating a pool and adding a post to it
    update_post(post, :tags => "tag1 tag2 pool:new_pool")
    post.reload
    assert_equal("tag1 tag2", post.cached_tags)
    pool = Pool.find_by_name("new_pool")
    assert_not_nil(pool)
    assert_not_nil(PoolPost.find(:first, :conditions => ["pool_id = ? AND post_id = ?", pool.id, post.id]))
    
    # Test adding to an existing pool and case insensitivity
    post2 = create_post("tag3 pool:NEW_POOL", :file => upload_jpeg("#{RAILS_ROOT}/test/mocks/test/test2.jpg"))
    assert_not_nil(PoolPost.find(:first, :conditions => ["pool_id = ? AND post_id = ?", pool.id, post2.id]))

    # Test removing a post from a pool
    update_post(post, :tags => "tag1 tag2 -pool:new_pool")
    post.reload
    assert_equal("tag1 tag2", post.cached_tags)
    assert_nil(PoolPost.find(:first, :conditions => ["pool_id = ? AND post_id = ?", pool.id, post.id]))
    
    # Test setting the rating
    update_post(post, :tags => "tag1 tag2 rating:e")
    post.reload
    assert_equal("e", post.rating)
    
    # Test setting the parent
    update_post(post, :tags => "tag1 tag2 parent:1")
    post.reload
    assert_equal(1, post.parent_id)
    assert(Post.find(1).has_children?, "Post should have children")
    
    # Test resetting the parent
    update_post(post, :tags => "tag1 tag2 parent:#{post.id}")
    post.reload
    assert_nil(post.parent_id)
    assert(!Post.find(1).has_children?, "Post should not have children")
    
    # Test access checks for existing pool
    pool = create_pool(:name => "hoge")
    update_post(post, :tags => "pool:hoge", :updater_user_id => 4)
    assert_nil(PoolPost.find(:first, :conditions => ["pool_id = ? AND post_id = ?", pool.id, post.id]))
  end
  
  def test_tagging
    post = create_post("tag1 tag2")
    
    # Test the Post#has_tag? method
    assert(post.has_tag?("tag1"), "Post#has_tag? should have succeeded")
    assert(!post.has_tag?("tag"), "Post#has_tag? should have succeeded")
    assert(!post.has_tag?("bababa"), "Post#has_tag? should have succeeded")
    
    # Test simple tagging
    update_post(post, :tags => "tag3 tag4")
    post.reload
    assert_equal("tag3 tag4", post.cached_tags)
    assert_equal(0, Post.count_by_sql(Post.generate_sql("tag1", :count => true)))
    assert_equal(0, Post.count_by_sql(Post.generate_sql("tag2", :count => true)))
    assert_equal(1, Post.count_by_sql(Post.generate_sql("tag3", :count => true)))
    assert_equal(1, Post.count_by_sql(Post.generate_sql("tag4", :count => true)))
    
    update_post(post, :tags => "general:tag3 artist:tag3")
    assert_equal("tag3", post.cached_tags)
    assert_equal(0, Post.count_by_sql(Post.generate_sql("tag1", :count => true)))
    assert_equal(0, Post.count_by_sql(Post.generate_sql("tag2", :count => true)))
    assert_equal(1, Post.count_by_sql(Post.generate_sql("tag3", :count => true)))
    assert_equal(0, Post.count_by_sql(Post.generate_sql("tag4", :count => true)))    
  end
  
  def test_voting
    post = create_post("tag1 tag2")
    assert_raise(PostVoteMethods::PrivilegeError) {post.vote!(User.find(4), 1)}
    post.reload
    assert_equal(0, post.score)
    assert_nothing_raised {post.vote!(User.find(3), 1)}
    post.reload
    assert_equal(1, post.score)
    assert_raise(PostVoteMethods::AlreadyVotedError) {post.vote!(User.find(3), -1)}
    post.reload
    assert_equal(1, post.score)
  end
  
  def test_destroy_with_reason
    post = create_post("tag1 tag2")
    Post.destroy_with_reason(post.id, "bad bad bad", User.find(1))
    post.reload
    assert(post.is_deleted?, "Post should be deleted")
    assert_not_nil(post.flag_detail)
    assert_equal("bad bad bad", post.flag_detail.reason)
  end
  
  def test_flagging_and_approval
    post = create_post("tag1 tag2")
    post.flag!("bad bad bad", 1)
    post.reload
    assert(post.is_flagged?, "Post should be flagged")
    assert_not_nil(post.flag_detail)
    assert_equal("bad bad bad", post.flag_detail.reason)
    
    post.approve!(1)
    post.reload
    assert(post.is_active?, "Post should be active")
    assert(post.flag_detail.is_resolved?, "Flag detail should be resolved")
    assert_equal(1, post.approver_id)
  end
  
  # The following search methods assume Tag.parse_query works.
  
  def test_search_simple
    p1 = create_post("tag1")
    p2 = create_post("tag2", :file => upload_jpeg("#{RAILS_ROOT}/test/mocks/test/test2.jpg"))
    p3 = create_post("tag3", :file => upload_jpeg("#{RAILS_ROOT}/test/mocks/test/test2.jpg"))
    matches = search_posts("tag1")
    assert_equal(1, matches.size)
    assert_equal(p1.id, matches[0].id)
  end
  
  def test_search_intersection_with_two_tags
    p1 = create_post("tag1 tag2")
    p2 = create_post("tag1", :file => upload_jpeg("#{RAILS_ROOT}/test/mocks/test/test2.jpg"))
    p3 = create_post("tag2", :file => upload_jpeg("#{RAILS_ROOT}/test/mocks/test/test3.jpg"))
    matches = search_posts("tag1 tag2")
    assert_equal(1, matches.size)
    assert_equal(p1.id, matches[0].id)
  end
  
  def test_search_intersection_with_three_tags
    p1 = create_post("tag1 tag2 tag3")
    p2 = create_post("tag1 tag2", :file => upload_jpeg("#{RAILS_ROOT}/test/mocks/test/test2.jpg"))
    p3 = create_post("tag2 tag3", :file => upload_jpeg("#{RAILS_ROOT}/test/mocks/test/test3.jpg"))
    p4 = create_post("tag1", :file => upload_jpeg("#{RAILS_ROOT}/test/mocks/test/test4.jpg"))
    p5 = create_post("tag2", :file => upload_jpeg("#{RAILS_ROOT}/test/mocks/test/test5.jpg"))
    p6 = create_post("tag3", :file => upload_jpeg("#{RAILS_ROOT}/test/mocks/test/test6.jpg"))
    matches = search_posts("tag1 tag2 tag3")
    assert_equal(1, matches.size)
    assert_equal(p1.id, matches[0].id)
  end
  
  def test_search_negated_tags
    Post.find(:all).each {|x| x.delete_from_database}
    
    p1 = create_post("tag1 tag2 tag3")
    p2 = create_post("tag1 tag2", :file => upload_jpeg("#{RAILS_ROOT}/test/mocks/test/test2.jpg"))
    p3 = create_post("tag2 tag3", :file => upload_jpeg("#{RAILS_ROOT}/test/mocks/test/test3.jpg"))
    p4 = create_post("tag1", :file => upload_jpeg("#{RAILS_ROOT}/test/mocks/test/test4.jpg"))
    p5 = create_post("tag2", :file => upload_jpeg("#{RAILS_ROOT}/test/mocks/test/test5.jpg"))
    p6 = create_post("tag3", :file => upload_jpeg("#{RAILS_ROOT}/test/mocks/test/test6.jpg"))

    matches = search_posts("-tag3", :user => User.find(1))
    assert_equal(3, matches.size)
    assert_equal(p2.id, matches[0].id)
    assert_equal(p4.id, matches[1].id)
    assert_equal(p5.id, matches[2].id)
    
    assert_raises(RuntimeError) do
      search_posts("-tag3", :user => AnonymousUser.new)
    end

    matches = search_posts("tag1 -tag3")
    assert_equal(2, matches.size)
    assert_equal(p2.id, matches[0].id)
    assert_equal(p4.id, matches[1].id)
  end
  
  def test_search_by_source
    p1 = create_post("tag1", :source => "http://hoge.com/test.jpg")
    
    matches = search_posts("source:http://hoge.com/test.jpg")
    assert_equal(1, matches.size)
    assert_equal(p1.id, matches[0].id)
    
    matches = search_posts("source:http://hoge.com/something_else.jpg")
    assert_equal(0, matches.size)

    matches = search_posts("source:http://hoge.com/*")
    assert_equal(1, matches.size)
    assert_equal(p1.id, matches[0].id)
  end
  
  def test_search_pattern
    p1 = create_post("hoge nushi", :file => upload_jpeg("#{RAILS_ROOT}/test/mocks/test/test1.jpg"))
    p2 = create_post("hoge", :file => upload_jpeg("#{RAILS_ROOT}/test/mocks/test/test2.jpg"))
    
    matches = search_posts("*oge")
    assert_equal(2, matches.size)
    
    matches = search_posts("nu*")
    assert_equal(1, matches.size)
    
    matches = search_posts("jaoooo*")
    assert_equal(0, matches.size)
  end
  
  def test_special_characters
    p1 = create_post("\\a", :file => upload_jpeg("#{RAILS_ROOT}/test/mocks/test/test1.jpg"))
    p2 = create_post("'a", :file => upload_jpeg("#{RAILS_ROOT}/test/mocks/test/test2.jpg"))
    p3 = create_post("?a", :file => upload_jpeg("#{RAILS_ROOT}/test/mocks/test/test3.jpg"))
    
    assert_equal(1, search_posts("\\a").size)
    assert_equal(1, search_posts("'a").size)
    assert_equal(1, search_posts("?a").size)
  end
  
  # TODO: additional search tests
end
