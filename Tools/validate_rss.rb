#!/usr/bin/env ruby

require 'rexml/document'
require 'uri'
require 'date'
require 'net/http'

class PodcastRSSValidator
  def initialize(input)
    @input = input
    @errors = []
    @warnings = []
    @media_urls = {}
    @guids = {}
  end

  def validate
    if url?(@input)
      puts "Validating RSS from URL: #{@input}"
    else
      puts "Validating RSS file: #{@input}"
    end
    puts "=" * 50

    begin
      content = get_content(@input)
      doc = REXML::Document.new(content)

      validate_basic_structure(doc)
      validate_channel(doc)
      validate_episodes(doc)

      print_results

    rescue REXML::ParseException => e
      puts "❌ XML Parse Error: #{e.message}"
      return false
    rescue => e
      puts "❌ Error: #{e.message}"
      return false
    end

    @errors.empty?
  end

  private

  def url?(input)
    uri = URI.parse(input)
    uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
  rescue URI::InvalidURIError
    false
  end

  def get_content(input)
    if url?(input)
      fetch_from_url(input)
    else
      read_from_file(input)
    end
  end

  def fetch_from_url(url)
    uri = URI.parse(url)

    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
      request = Net::HTTP::Get.new(uri)
      response = http.request(request)

      unless response.code == '200'
        raise "HTTP Error: #{response.code} #{response.message}"
      end

      response.body
    end
  end

  def read_from_file(filepath)
    unless File.exist?(filepath)
      raise "File not found: #{filepath}"
    end

    File.read(filepath)
  end

  def validate_basic_structure(doc)
    # Check for RSS root element
    rss_element = doc.root
    if rss_element.nil? || rss_element.name != 'rss'
      @errors << "Missing or invalid RSS root element"
      return
    end

    # Check RSS version
    version = rss_element.attributes['version']
    if version != '2.0'
      @warnings << "RSS version is '#{version}', expected '2.0'"
    end

    # Check for channel element
    channel = rss_element.elements['channel']
    if channel.nil?
      @errors << "Missing channel element"
    end
  end

  def validate_channel(doc)
    channel = doc.root&.elements['channel']
    return unless channel

    puts "\n📡 Validating Channel..."

    # Required fields for PodcastRSS
    required_fields = {
      'title' => 'Channel title',
      'description' => 'Channel description'
    }

    required_fields.each do |field, description|
      element = channel.elements[field]
      if element.nil? || element.text.to_s.strip.empty?
        @errors << "Missing required channel field: #{field} (#{description})"
      else
        puts "✅ #{description}: #{truncate(element.text)}"
      end
    end

    # Check iTunes image (required for PodcastRSS)
    itunes_image = channel.elements['itunes:image']
    if itunes_image.nil?
      @errors << "Missing required iTunes image (itunes:image)"
    else
      href = itunes_image.attributes['href']
      if href.nil? || href.strip.empty?
        @errors << "iTunes image missing href attribute"
      else
        if valid_url?(href)
          puts "✅ iTunes image: #{href}"
        else
          @errors << "iTunes image href is not a valid URL: #{href}"
        end
      end
    end

    # Check atom:link elements (required array, can be empty)
    atom_links = channel.elements.to_a('atom:link')
    puts "✅ Atom links: #{atom_links.length} found"

    # Optional but common fields
    optional_fields = {
      'link' => 'Channel website',
      'language' => 'Language',
      'itunes:author' => 'iTunes author',
      'itunes:owner' => 'iTunes owner'
    }

    optional_fields.each do |field, description|
      element = channel.elements[field]
      if element
        puts "✅ #{description}: #{truncate(element.text || element.to_s)}"
      else
        puts "⚠️  Optional #{description} not found"
      end
    end
  end

  def validate_episodes(doc)
    channel = doc.root&.elements['channel']
    return unless channel

    items = channel.elements.to_a('item')

    puts "\n🎧 Validating Episodes..."
    puts "Found #{items.length} episodes"

    if items.empty?
      @errors << "No episodes found in RSS feed"
      return
    end

    items.each_with_index do |item, index|
      validate_episode(item, index + 1)
    end

    check_for_duplicates
  end

  def validate_episode(item, episode_num)
    puts "\n--- Episode #{episode_num} ---"

    # Required fields for Episode struct
    required_fields = {
      'title' => 'Episode title',
      'enclosure' => 'Media enclosure',
      'guid' => 'Episode GUID'
    }

    episode_valid = true

    required_fields.each do |field, description|
      element = item.elements[field]

      case field
      when 'title'
        if element.nil? || element.text.to_s.strip.empty?
          @errors << "Episode #{episode_num}: Missing #{description}"
          episode_valid = false
        else
          puts "✅ #{description}: #{truncate(element.text)}"
        end

      when 'enclosure'
        if element.nil?
          @errors << "Episode #{episode_num}: Missing enclosure element"
          episode_valid = false
        else
          url = element.attributes['url']
          if url.nil? || url.strip.empty?
            @errors << "Episode #{episode_num}: Enclosure missing URL attribute"
            episode_valid = false
          else
            if valid_url?(url)
              puts "✅ Media URL: #{truncate(url)}"
              # Track media URLs for duplicate checking
              if @media_urls[url]
                @media_urls[url] << episode_num
              else
                @media_urls[url] = [episode_num]
              end
            else
              @errors << "Episode #{episode_num}: Invalid enclosure URL: #{url}"
              episode_valid = false
            end
          end
        end

      when 'guid'
        if element.nil? || element.text.to_s.strip.empty?
          @errors << "Episode #{episode_num}: Missing GUID"
          episode_valid = false
        else
          guid = element.text.to_s.strip
          puts "✅ GUID: #{truncate(guid)}"
          # Track GUIDs for duplicate checking
          if @guids[guid]
            @guids[guid] << episode_num
          else
            @guids[guid] = [episode_num]
          end
        end
      end
    end

    # Check iTunes namespace (required container)
    itunes_fields = ['itunes:duration', 'itunes:image', 'itunes:explicit']
    itunes_found = itunes_fields.any? { |field| item.elements[field] }

    if itunes_found
      puts "✅ iTunes namespace elements found"
    else
      @warnings << "Episode #{episode_num}: No iTunes namespace elements found"
    end

    # Optional but important fields
    optional_fields = {
      'description' => 'Episode description',
      'pubDate' => 'Publication date',
      'link' => 'Episode link'
    }

    optional_fields.each do |field, description|
      element = item.elements[field]
      if element && !element.text.to_s.strip.empty?
        if field == 'pubDate'
          # Validate RFC2822 date format
          begin
            Date.rfc2822(element.text)
            puts "✅ #{description}: #{element.text}"
          rescue ArgumentError
            @warnings << "Episode #{episode_num}: Invalid date format in pubDate: #{element.text}"
          end
        else
          puts "✅ #{description}: #{truncate(element.text)}"
        end
      else
        puts "⚠️  Optional #{description} not found"
      end
    end

    puts "Episode #{episode_num}: #{episode_valid ? '✅ Valid' : '❌ Invalid'}"
  end

  def valid_url?(url_string)
    uri = URI.parse(url_string)
    uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
  rescue URI::InvalidURIError
    false
  end

  def truncate(text, length = 60)
    return text if text.length <= length
    "#{text[0, length]}..."
  end

  def check_for_duplicates
    puts "\n🔍 Checking for Duplicates..."

    # Check for duplicate media URLs
    duplicate_urls = @media_urls.select { |url, episodes| episodes.length > 1 }
    unless duplicate_urls.empty?
      puts "\n❌ Duplicate Media URLs Found:"
      duplicate_urls.each do |url, episodes|
        @errors << "Duplicate media URL found in episodes #{episodes.join(', ')}: #{truncate(url)}"
        puts "   • Episodes #{episodes.join(', ')} share URL: #{truncate(url)}"
      end
    else
      puts "✅ No duplicate media URLs found"
    end

    # Check for duplicate GUIDs
    duplicate_guids = @guids.select { |guid, episodes| episodes.length > 1 }
    unless duplicate_guids.empty?
      puts "\n❌ Duplicate GUIDs Found:"
      duplicate_guids.each do |guid, episodes|
        @errors << "Duplicate GUID found in episodes #{episodes.join(', ')}: #{truncate(guid)}"
        puts "   • Episodes #{episodes.join(', ')} share GUID: #{truncate(guid)}"
      end
    else
      puts "✅ No duplicate GUIDs found"
    end

    # Summary
    total_duplicates = duplicate_urls.length + duplicate_guids.length
    if total_duplicates == 0
      puts "\n✅ All episodes have unique media URLs and GUIDs"
    else
      puts "\n❌ Found #{total_duplicates} duplicate issues"
    end
  end

  def print_results
    puts "\n" + "=" * 50
    puts "VALIDATION RESULTS"
    puts "=" * 50

    if @errors.empty? && @warnings.empty?
      puts "🎉 RSS file is valid and compatible with PodcastRSS!"
    else
      unless @errors.empty?
        puts "\n❌ ERRORS (#{@errors.length}):"
        @errors.each { |error| puts "   • #{error}" }
      end

      unless @warnings.empty?
        puts "\n⚠️  WARNINGS (#{@warnings.length}):"
        @warnings.each { |warning| puts "   • #{warning}" }
      end

      if @errors.empty?
        puts "\n✅ No critical errors found. RSS should parse successfully."
      else
        puts "\n❌ Critical errors found."
      end
    end

    puts "\nSummary:"
    puts "  • Errors: #{@errors.length}"
    puts "  • Warnings: #{@warnings.length}"
    puts "  • Status: #{@errors.empty? ? 'VALID' : 'INVALID'}"
  end
end

# Main execution
if ARGV.length != 1
  puts "Usage: ruby validate_rss.rb <rss_file_path_or_url>"
  puts "Examples:"
  puts "  ruby validate_rss.rb wakingup.rss"
  puts "  ruby validate_rss.rb https://example.com/podcast.rss"
  exit 1
end

validator = PodcastRSSValidator.new(ARGV[0])
success = validator.validate

exit(success ? 0 : 1)
