CONFIG = {}

# The version of this Danbooru.
CONFIG["version"] = "1.12.1"

# The default name to use for anyone who isn't logged in.
CONFIG["default_guest_name"] = "Anonymous"

# Set to true to require an e-mail address to register.
CONFIG["enable_account_email_activation"] = false

# This is a salt used to make dictionary attacks on account passwords harder.
CONFIG["password_salt"] = "choujin-steiner"

# Set to true to allow new account signups.
CONFIG["enable_signups"] = true

# Newly created users start at this level. Set this to 3 if you want everyone
# to start out as a privileged member.
CONFIG["starting_level"] = 2

# What method to use to store images.
# local_flat: Store every image in one directory.
# local_hierarchy: Store every image in a hierarchical directory, based on the post's MD5 hash. On some file systems this may be faster.
# local_flat_with_amazon_s3_backup: Store every image in a flat directory, but also save to an Amazon S3 account for backup.
# amazon_s3: Save files to an Amazon S3 account.
# remote_hierarchy: Some images will be stored on separate image servers using a hierarchical directory.
CONFIG["image_store"] = :local_flat

# Only used when image_store == :remote_hierarchy. An array of image servers (use http://domain.com format).
CONFIG["image_servers"] = []

# These three configs are only relevant if you're using the Amazon S3 image store.
CONFIG["amazon_s3_access_key_id"] = ""
CONFIG["amazon_s3_secret_access_key"] = ""
CONFIG["amazon_s3_bucket_name"] = ""

# This enables various caching mechanisms. You must have memcache (and the memcache-client ruby gem) installed in order for caching to work.
CONFIG["enable_caching"] = false

# The server and port where the memcache client can be accessed. Only relevant if you enable caching.
CONFIG["memcache_servers"] = ["localhost:4000"]

# Any post rated safe or questionable that has one of the following tags will automatically be rated explicit.
CONFIG["explicit_tags"] = %w(pussy penis cum anal vibrator dildo masturbation oral_sex sex paizuri penetration guro rape asshole footjob handjob blowjob cunnilingus anal_sex)

# After a post receives this many posts, new comments will no longer bump the post in comment/index.
CONFIG["comment_threshold"] = 40

# Members cannot post more than X posts in a day.
CONFIG["member_post_limit"] = 16

# Members cannot post more than X comments in an hour.
CONFIG["member_comment_limit"] = 2

# This allows posts to have parent-child relationships. However, this requires manually updating the post counts stored in table_data by periodically running the script/maintenance script.
CONFIG["enable_parent_posts"] = false

# Show only the first page of post/index to visitors.
CONFIG["show_only_first_page"] = false

CONFIG["enable_reporting"] = false

# Enable some web server specific optimizations. Possible values include: apache, nginx, lighttpd.
CONFIG["web_server"] = "apache"

# Show a link to Trac.
CONFIG["enable_trac"] = true

# DEPRECATED IN DANBOORU 1.13.0
# Enable this if you want explicit posts to be hidden from unprivileged users.
CONFIG["hide_explicit_posts"] = false

# DEPRECATED IN DANBOORU 1.13.0
# Enable this if you want explicit and questionable posts to be hidden from unprivileged users.
CONFIG["hide_questionable_posts"] = false

# DEPRECATED IN DANBOORU 1.13.0
# Enable this if you want posts tagged with loli or shota to be hidden from unprivileged users.
CONFIG["hide_loli_posts"] = false

# TAKES EFFECT IN DANBOORU 1.13.0
# Defines the various user levels. You should not remove any of the default ones. When Danbooru starts up, the User model will have several methods automatically defined based on what this config contains. For this reason you should only use letters, numbers, and spaces (spaces will be replaced with underscores). Example: is_member?, is_member_or_lower?, is_member_or_higher?
CONFIG["user_levels"] = {
  "Unactivated" => -1,
  "Blocked" => 0,
  "Member" => 2,
  "Privileged" => 3,
  "Mod" => 10,
  "Admin" => 20
}

# TAKES EFFECT IN DANBOORU 1.13.0
# Defines the various tag types.
CONFIG["tag_types"] = {
  "General" => 0,
  "Artist" => 1,
  "Copyright" => 3,
  "Character" => 4
}

# TAKES EFFECT IN DANBOORU 1.13.0
# Determine who can see a post. Note that since this is a block, return won't work. Use break.
CONFIG["can_see_post"] = lambda do |user, post|
  # By default, only deleted posts are hidden.
  break post.status != 'deleted'
  
  # Some examples:
  #
  # Hide post if user isn't privileged and post is not safe:
  # break post.rating != 'e' || (user != nil && user.privileged?)
  #
  # Hide post if user isn't a mod and post has the loli tag:
  # break post.has_tag?("loli") 
end

# TAKES EFFECT IN DANBOORU 1.13.0
# Determines who can see ads. Action will be a symbol, either :show (for post/show) or :index (for post/index). For post/show, post_or_params will be the post. For post/index, post_or_params will be the parameters. Note that since this is a block, return won't work. Use break.
CONFIG["can_see_ads"] = lambda do |user, action, post_or_params|
  # By default, only show ads to non-priv users.
  break user == nil || user.is_member_or_lower?
end
