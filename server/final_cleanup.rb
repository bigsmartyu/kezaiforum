# frozen_string_literal: true

# Run inside the Discourse container with RAILS_ENV=production.

admin = User.find_by!(username: "admin", admin: true)
removed = []

User.where("id > 0").where.not(id: admin.id).find_each do |user|
  removed << "#{user.id}:#{user.username}"
  UserDestroyer.new(admin).destroy(user, delete_posts: true, context: "科仔交流社区上线前清理")
end

Reviewable.where(status: Reviewable.statuses[:pending]).find_each(&:destroy!)
admin.user_auth_tokens.destroy_all

remaining = User.where("id > 0")
ordinary = remaining.where(admin: false)

puts "CLEANUP_OK"
puts "REMOVED=#{removed.join(',')}"
puts "POSITIVE_USERS=#{remaining.count}"
puts "ORDINARY_USERS=#{ordinary.count}"
puts "PENDING_REVIEWS=#{Reviewable.where(status: Reviewable.statuses[:pending]).count}"
puts "ADMIN_TOKENS=#{admin.user_auth_tokens.count}"
puts "REMAINING=#{remaining.pluck(:id, :username, :name, :admin).map { |row| row.join('|') }.join(',')}"
