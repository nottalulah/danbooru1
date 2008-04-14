module TagMethods
  module ParseMethods
    module ClassMethods
      def scan_query(query)
        query.to_s.downcase.scan(/\S+/).uniq
      end

      def scan_tags(tags)
        tags.to_s.gsub(/[*%,]/, "").downcase.scan(/\S+/).uniq
      end

      def parse_helper(range, type = :integer)
        cast = lambda do |x|
          if type == :integer
            x.to_i
          elsif type == :float
            x.to_f
          elsif type == :date
            x.to_date
          end
        end

        # "1", "0.5", "5.", ".5":
        # (-?(\d+(\.\d*)?|\d*\.\d+))
        case range
        when /^(.+?)\.\.(.+)/
          return [:between, cast[$1], cast[$2]]

        when /^<=(.+)/, /^\.\.(.+)/
          return [:lte, cast[$1]]

        when /^<(.+)/
          return [:lt, cast[$1]]

        when /^>=(.+)/, /^(.+)\.\.$/
          return [:gte, cast[$1]]

        when /^>(.+)/
          return [:gt, cast[$1]]

        else
          return [:eq, cast[range]]

        end
      end

    # Parses a query into three sets of tags: reject, union, and intersect.
    #
    # === Parameters
    # * +query+: String, array, or nil. The query to parse.
    # * +options+: A hash of options.
      def parse_query(query, options = {})
        q = Hash.new {|h, k| h[k] = []}

        scan_query(query).each do |token|
          if token =~ /^(unlocked|deleted|user|fav|md5|-rating|rating|width|height|mpixels|score|source|id|date|pool|parent|order|change):(.+)$/
            if $1 == "user"
              q[:user] = $2
            elsif $1 == "fav"
              q[:fav] = $2
            elsif $1 == "md5"
              q[:md5] = $2
            elsif $1 == "-rating"
              q[:rating_negated] = $2
            elsif $1 == "rating"
              q[:rating] = $2
            elsif $1 == "id"
              q[:post_id] = parse_helper($2)
            elsif $1 == "width"
              q[:width] = parse_helper($2)
            elsif $1 == "height"
              q[:height] = parse_helper($2)
            elsif $1 == "mpixels"
              q[:mpixels] = parse_helper($2, :float)
            elsif $1 == "score"
              q[:score] = parse_helper($2)
            elsif $1 == "source"
              q[:source] = $2.gsub('\\', '\\\\').gsub('%', '\\%').gsub('_', '\\_').gsub(/\*/, '%') + "%"
            elsif $1 == "date"
              q[:date] = parse_helper($2, :date)
            elsif $1 == "pool"
              q[:pool] = $2
              if q[:pool] =~ /^(\d+)$/
                q[:pool] = q[:pool].to_i
              end
            elsif $1 == "parent"
              if $2 == "none"
                q[:parent_id] = false
              else
                q[:parent_id] = $2.to_i
              end
            elsif $1 == "order"
              q[:order] = $2
            elsif $1 == "unlocked"
              if $2 == "rating"
                q[:unlocked_rating] = true
              end
            elsif $1 == "deleted" && $2 == "true"
              q[:deleted_only] = true
            elsif $1 == "change"
              q[:change] = parse_helper($2)
            end
          elsif token[0] == ?-
            q[:exclude] << token[1..-1]
          elsif token[0] == ?~
            q[:include] << token[1..-1]
          elsif token.include?("*")
            q[:include] += find(:all, :conditions => ["name LIKE ? ESCAPE '\\\\'", token.to_escaped_for_sql_like], :select => "name, post_count", :limit => 20).map {|i| i.name}
          elsif token == "@unlockedrating"
            q[:unlocked_rating] = true
          else
            q[:related] << token
          end
        end

        unless options[:skip_aliasing]
          q[:exclude] = TagAlias.to_aliased(q[:exclude])
          q[:include] = TagAlias.to_aliased(q[:include])
          q[:related] = TagAlias.to_aliased(q[:related])
        end

        return q
      end
    end

    def self.included(m)
      m.extend(ClassMethods)
    end
  end
end