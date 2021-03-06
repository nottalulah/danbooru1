class TagSubscription < ActiveRecord::Base
  belongs_to :user
  before_create :initialize_post_ids
  before_save :normalize_name
  before_save :limit_tag_count
  named_scope :visible, :conditions => "is_visible_on_profile = TRUE"

  def normalize_name
    self.name = name.gsub(/\W/, "_")
  end
  
  def initialize_post_ids
    process
  end
  
  def limit_tag_count
    self.tag_query = tag_query.scan(/\S+/).slice(0, 20).join(" ")
  end
  
  def process
    tags = tag_query.scan(/\S+/)
    post_ids = []
    tags.each do |tag|
      post_ids += Post.find_by_tags(tag, :limit => CONFIG["tag_subscription_post_limit"] / 3, :select => "p.id", :order => "p.id desc").map(&:id)
    end
    self.cached_post_ids = post_ids.sort.reverse.slice(0, CONFIG["tag_subscription_post_limit"]).join(",")
  end
  
  def self.find_tags(subscription_name)
    if subscription_name =~ /^(.+?):(.+)$/
      user_name = $1
      sub_group = $2
    else
      user_name = subscription_name
      sub_group = nil
    end
    
    user = User.find_by_name(user_name)
    if user
      if sub_group
        find(:all, :conditions => ["user_id = ? AND name ILIKE ? ESCAPE E'\\\\'", user.id, sub_group.to_escaped_for_sql_like]).map {|x| x.tag_query.split(/ /)}.flatten
      else
        find(:all, :conditions => ["user_id = ?", user.id]).map {|x| x.tag_query.split(/ /)}.flatten
      end
    else
      []
    end        
  end
  
  def self.find_post_ids(user_id, name = nil, limit = CONFIG["tag_subscription_post_limit"])
    if name
      find(:all, :conditions => ["user_id = ? AND name ILIKE ? ESCAPE E'\\\\'", user_id, name.to_escaped_for_sql_like], :select => "id, cached_post_ids").map {|x| x.cached_post_ids.split(/,/)}.flatten.uniq.map(&:to_i).sort.reverse.slice(0, limit)
    else
      find(:all, :conditions => ["user_id = ?", user_id], :select => "id, cached_post_ids").map {|x| x.cached_post_ids.split(/,/)}.flatten.uniq.map(&:to_i).sort.reverse.slice(0, limit)
    end
  end
  
  def self.find_posts(user_id, name = nil, limit = CONFIG["tag_subscription_post_limit"])
    Post.find(:all, :conditions => ["id in (?) AND rating = 's'", find_post_ids(user_id, name, limit)], :order => "id DESC", :limit => limit)
  end
  
  def self.process_all
    find(:all).each do |tag_subscription|
      if $job_task_daemon_active != false && tag_subscription.user.is_privileged_or_higher?
        begin
          tag_subscription.process
          tag_subscription.save
        rescue Exception => x
raise
          # fail silently
        end
      end
    end
  end
end
