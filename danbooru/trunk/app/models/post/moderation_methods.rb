module PostModerationMethods
  def mod_hide!(user_id)
    unless ModQueuePost.exists?(["user_id = ? AND post_id = ?", user_id, id])
      ModQueuePost.create(:user_id => user_id, :post_id => id)
    end
  end
end
