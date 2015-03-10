# This script ensures that all dependencies (NPM and Bower) are checked against a whitelist of commits.
# Only non-minified source if checked, so always make sure to minify dependencies yourself. Development 
# tools - and perhaps some very large common libraties - are skipped in these checks.

# npm-shrinkwrap.json should be present (e.g. generated with Grunt or 
# "npm shrinkwrap"). This contains the list of all (sub) dependencies.

# Ruby is needed as well as the following gems:
# gem install json

# Github API requires authentication because of rate limiting. So run with:
# GITHUB_USER=username GITHUB_PASSWORD=password ruby check-dependencies.rb

require 'json'
require 'open-uri'

whitelist = JSON.parse(File.read('dependency-whitelist.json'))

##########
# Common #
##########

def first_two_digits_match_or_lower_than(left, right)
  # e.g. "~1.1.2" and "1.1.3" matches
  #      "~1.1.0" and "1.2.0" matches
  a = left.gsub("~", "")
  b = right.gsub("~", "")
  
  a.split(".")[0].to_i <= b.split(".")[0].to_i && a.split(".")[1].to_i <= b.split(".")[1].to_i
end


def getJSONfromURL(url)
  if ENV['GITHUB_USER'] and ENV['GITHUB_PASSWORD']
    http_options = {:http_basic_authentication=>[ENV['GITHUB_USER'], ENV['GITHUB_PASSWORD']]}
    json = JSON.load(open(url, http_options))
  else
    json = JSON.load(open(url))
  end  
  return json
end
# apply_math = lambda do |auth, , nom|
#   a.send(fn, b)
# end
 
# add = apply_math.curry.(:+)
# subtract = apply_math.curry.(:-)
# multiply = apply_math.curry.(:*)
# divide = apply_math.curry.(:/)


def check_commits!(deps, whitelist, output_deps, type)
  
  deps.keys.each do |key|
    if whitelist["ignore"].include? key # Skip check
      unless ["angular", "angular-mocks", "angular-animate", "angular-bootstrap", "angular-cookies", "angular-sanitize", "bootstrap-css-only"].include? key   # Skip package altoghether 
        output_deps.delete(key)
      end
      next
    end

    dep = deps[key]
    if whitelist[key]
      # puts key
      # For Bower it expects a version formatted like "1.2.3" or "~1.2.3". It will use the highest match exact version.
      requested_version = type == :npm ? dep['version'] : dep
      
      requested_version = requested_version.split("#").last # e.g. "pernas/angular-password-entropy#0.1.3" -> "0.1.3"
      
      if !(["~", "0", "1", "2", "3", "4", "5", "6","7", "8", "9"].include?(requested_version[0]))
        abort "Version format not supported: #{ key } #{ requested_version }"
      elsif requested_version[0] != "~" && requested_version <= whitelist[key]['version']
      elsif requested_version[0] == "~" and first_two_digits_match_or_lower_than(requested_version, whitelist[key]['version'])
      else
        abort "#{ key } version #{ requested_version } has not been whitelisted yet. Most recent: #{ whitelist[key]['version'] }"
        # TODO: generate URL showing all commits since the last whitelisted one
        next
      end

      tags = getJSONfromURL("https://api.github.com/repos/#{ whitelist[key]["repo"] }/tags")
      tag = nil

      tags.each do |candidate|
        if candidate["name"] == "v#{ requested_version }" || candidate["name"] == requested_version
          tag = candidate
          break
        elsif requested_version[0] == "~" && first_two_digits_match_or_lower_than(requested_version, candidate["name"])
          # TODO: warn if not using the latest version in range
          
          tag = candidate
          break
        end
      end

      if !tag.nil?
        # Check if tagged commit matches whitelist commit (this or earlier version)
        if whitelist[key]["commits"].include?(tag["commit"]["sha"])
          if type == :npm
            output_deps[key] = {"version" => "#{ whitelist[key]["repo"] }##{ tag["commit"]["sha"] }"}
          else
            output_deps[key] = "#{ whitelist[key]["repo"] }##{ tag["commit"]["sha"] }"
          end

        else
          abort "Error: v#{ dep['version'] } of #{ key } does not match the whitelist."
          next
        end


      else
        puts "Warn: no Github tag found for v#{ dep['version'] } of #{ key }."
        # Look through the list of commits instead:
        
        commits = getJSONfromURL("https://api.github.com/repos/#{ whitelist[key]["repo"] }/commits")
        commit = nil

        commits.each do |candidate|
          if candidate["sha"] == whitelist[key]['commits'].first
            commit = candidate

            break
          end
        end

        if !commit.nil?
          if type == :npm
            output_deps[key] = {"version" => "#{ whitelist[key]["repo"] }##{ commit["sha"] }"}
          else
            output_deps[key] = "#{ whitelist[key]["repo"] }##{ commit["sha"] }"
          end
        else
          puts "Error: no Github commit #{ whitelist[key]["commits"].first } of #{ key }."
          next
        end
      end

      if type == :npm && deps[key]["dependencies"]
        output_deps[key]["dependencies"] = {}
        check_commits!(deps[key]["dependencies"], whitelist, output_deps[key]["dependencies"], type)
      end
    else
      abort "#{key} not whitelisted!"
    end
  end
end

#########
# NPM   #
#########

shrinkwrap = JSON.parse(File.read('npm-shrinkwrap.json'))
deps = shrinkwrap["dependencies"]

output = JSON.parse(File.read('npm-shrinkwrap.json')) # More reliable than cloning
output_deps = output["dependencies"]

check_commits!(deps, whitelist, output_deps, :npm)

# TODO: shrinkwrap each subdependency and/or disallow packages to install dependencies themselves?

File.write("build/npm-shrinkwrap.json", JSON.pretty_generate(output))


package = JSON.parse(File.read('package.json'))

output = package.dup

# output["dependencies"] = {}

# Remove unessential dev dependencies:
output["devDependencies"].keys.each do |devDep|
  output["devDependencies"].delete(devDep) unless ["grunt-contrib-clean", "grunt-contrib-concat", "grunt-surround", "grunt-contrib-coffee"].include?(devDep)
end

output.delete("author")
output.delete("contributors")
output.delete("homepage")
output.delete("bugs")
output.delete("license")
output.delete("repository")
output["scripts"].delete("test")
if package["name"] == "My-Wallet-HD"
  output["scripts"]["postinstall"] = "browserify -s Browserify ../browserify-imports.js > browserify.js && cd node_modules/bip39 && npm run compile && mv bip39.js ../.. && cd ../.. && cp node_modules/xregexp/xregexp-all.js . && cd node_modules/sjcl && ./configure --with-sha1 && make && cd - && cp node_modules/sjcl/sjcl.js ."
elsif package["name"] == "angular-blockchain-wallet"
  output["scripts"].delete("postinstall")
else
  abort("Package renamed? " + package["name"])
end

File.write("build/package.json", JSON.pretty_generate(output))


#########
# Bower #
#########

bower = JSON.parse(File.read('bower.json'))
output = bower.dup
output.delete("authors")
output.delete("main")
output.delete("ignore")
output.delete("license")
output.delete("keywords")
# output.delete("devDependencies") # TODO don't load LocalStorageModule in production

deps = bower["dependencies"]

check_commits!(deps, whitelist, output["dependencies"], :bower)

File.write("build/bower.json", JSON.pretty_generate(output))