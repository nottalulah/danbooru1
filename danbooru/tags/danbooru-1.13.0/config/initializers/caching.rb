if CONFIG["enable_caching"]
  require 'memcache_util'
  require 'cache'
  require 'memcache_util_store'
  
  CACHE = MemCache.new :c_threshold => 10_000, :compression => true, :debug => false, :namespace => CONFIG["app_name"], :readonly => false, :urlencode => false
  CACHE.servers = CONFIG["memcache_servers"]
end
