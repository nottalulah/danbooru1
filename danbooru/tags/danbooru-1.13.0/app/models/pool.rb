class Pool < ActiveRecord::Base
  class PostAlreadyExistsError < Exception; end
  
  belongs_to :user
  validates_uniqueness_of :name
  before_save :normalize_name
  
  def normalize_name
    self.name = self.name.gsub(/\s/, "_")
  end
  
  def pretty_name
    self.name.gsub(/_/, " ")
  end
  
  def add_post(post_id, seq = nil)
    if PoolPost.find(:first, :conditions => ["pool_id = ? and post_id = ?", self.id, post_id])
      raise PostAlreadyExistsError
    end

    transaction do
      Cache.expire(:post_id => post_id)
      update_attributes(:updated_at => Time.now)
      PoolPost.create(:pool_id => self.id, :post_id => post_id, :sequence => seq.to_i)
    end
  end
  
  def remove_post(post_id)
    Cache.expire(:post_id => post_id)
    PoolPost.destroy_all(["pool_id = ? and post_id = ?", self.id, post_id])
  end

  def api_attributes
    return {
      :id => id,
      :name => name,
      :created_at => created_at,
      :updated_at => updated_at,
      :user_id => user_id,
      :is_public => is_public,
      :post_count => post_count,
    }
  end

  def to_xml(options = {})
    options[:indent] ||= 2
    xml = options[:builder] ||= Builder::XmlMarkup.new(:indent => options[:indent])
    xml.pool(api_attributes) do
      xml.description(description)
      yield options[:builder]
    end
  end
end

class PoolPost < ActiveRecord::Base
  set_table_name "pools_posts"
  belongs_to :post
  belongs_to :pool
end
