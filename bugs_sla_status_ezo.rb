require 'net/https'
require 'uri'
require 'json'
require 'time'
require 'pry'

$current_time = Time.now.utc

def hotfix_rms
  url = 'https://pm.7vals.com/issues.json?utf8=%E2%9C%93&set_filter=1&sort=id%3Adesc&f%5B%5D=status_id&op%5Bstatus_id%5D=%3D&v%5Bstatus_id%5D%5B%5D=1&v%5Bstatus_id%5D%5B%5D=14&v%5Bstatus_id%5D%5B%5D=2&f%5B%5D=tracker_id&op%5Btracker_id%5D=%3D&v%5Btracker_id%5D%5B%5D=1&f%5B%5D=priority_id&op%5Bpriority_id%5D=%3D&v%5Bpriority_id%5D%5B%5D=6&v%5Bpriority_id%5D%5B%5D=7&f%5B%5D=cf_11&op%5Bcf_11%5D=%3D&v%5Bcf_11%5D%5B%5D=3&f%5B%5D=cf_21&op%5Bcf_21%5D=%21&v%5Bcf_21%5D%5B%5D=Specs+%2F+Design+Issue&f%5B%5D=&c%5B%5D=project&c%5B%5D=status&c%5B%5D=subject&c%5B%5D=assigned_to&c%5B%5D=created_on&c%5B%5D=updated_on&c%5B%5D=author&c%5B%5D=cf_21&c%5B%5D=category&group_by=&t%5B%5D=&include=journals'

  uri = URI.parse(url)
  req = Net::HTTP::Get.new(uri.request_uri)

  req['Content-Type'] = 'application/json'
  req['X-Redmine-API-Key'] = ENV['API_KEY']
  # req.body =

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.request(req)
end

def rm_with_notes(id)
  url = "https://pm.7vals.com/issues/#{id}.json?include=journals"

  uri = URI.parse(url)
  req = Net::HTTP::Get.new(uri.request_uri)

  req['Content-Type'] = 'application/json'
  req['X-Redmine-API-Key'] = ENV['API_KEY']

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.request(req)
end

def time_to_ago_str(time_obj)
  seconds_in_a_day   = 86400
  seconds_in_an_hour = 3600

  time_diff_in_seconds = $current_time - time_obj
  days, _rem = time_diff_in_seconds.divmod(seconds_in_a_day)

  if days
    "#{days} days ago"
  else
    hours, _rem = time_diff_in_seconds.divmod(seconds_in_an_hour)
    "#{hours} hours ago"
  end
end

def last_comment_time(rm_id)
  rm = parse_json(rm_with_notes(rm_id))['issue']
  filtered_journals = rm['journals'].reject { |journal| journal['notes'].nil? || journal['notes'] == '' }

  if filtered_journals.empty?
    'No Comment has been made'
  else
    last_comment_time = Time.parse(filtered_journals.last['created_on'])
    "Last Comment was made #{time_to_ago_str(last_comment_time)}"
  end
end

def reported_time(rm_created_on)
  reported_on_time = Time.parse(rm_created_on)
  "Reported #{time_to_ago_str(reported_on_time)}"
end

def parse_json(response)
  JSON.parse(response.body)
end

# filterting rms which are
# 1. Internal
# 2. Bug Type is 'Specs / Design Issue'
# 3. Not Created in Last Month
def filter_rms(issues)
  issues.reject do |issue|
    (!issue['category'].nil? && issue['category']['name'] == 'Internal ') || # So, Category is not internal
      (issue['custom_fields'].detect { |custom_field| custom_field['id'] == 21 }['value'] == 'Specs / Design Issue' ) || # So, Bug Type is not 'SPecs / Design Issue'
      (Time.parse(issue['created_on']) < ($current_time - 2678400)) # Issue is created in the last month
  end
end

def select_required_values(rms)
  rms.map { |rm| rm.slice('id', 'created_on', 'status', 'subject', 'assigned_to') }
end

def segregate_rms(rms)
  candidate_rms = { assigned: [], unassigned: [] }

  rms.each do |rm|
    if rm['assigned_to'].nil?
      candidate_rms[:unassigned] << rm
    else
      candidate_rms[:assigned] << rm
    end
  end

  candidate_rms
end

def write_to_file(candidate_rms)
  file_name = "#{$current_time.to_date}_Hotfix-Info.txt"
  File.open(file_name, 'w') do |file|
    file.write("Following are Assigned/In Progress Hot-fixes\n\n")
    candidate_rms[:assigned].each_with_index do |rm, index|
      file.write("#{index + 1}.  https://pm.7vals.com/issues/#{rm['id']}\n")
      file.write("\ta.  #{rm['subject']}\n")
      file.write("\tb.  #{last_comment_time(rm['id'])}\n")
    end

    file.write("\n\n\nFollowing are Unassigned Hot-fixes\n\n")
    candidate_rms[:unassigned].each_with_index do |rm, index|
      file.write("#{index + 1}.  https://pm.7vals.com/issues/#{rm['id']}\n")
      file.write("\ta.  #{rm['subject']}\n")
      file.write("\tb.  #{reported_time(rm['created_on'])}\n")
    end
  end
end

# parsed_rms    = parse_json(hotfix_rms)['issues']
# filtered_rms  = filter_rms(parsed_rms)
# sliced_rms    = select_required_values(filtered_rms)
# candidate_rms = segregate_rms(sliced_rms)
# write_to_file(candidate_rms)

write_to_file(
  segregate_rms(
    select_required_values(
      filter_rms(
        parse_json(hotfix_rms)['issues']
      )
    )
  )
)
