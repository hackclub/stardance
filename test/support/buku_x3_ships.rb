module BukuX3Ships
  def reviewed_ship(user:, minutes:, at:, reviewed_at: at, approved: minutes)
    project = Project.create!(title: "Buku #{SecureRandom.hex(4)}")
    project.memberships.create!(user: user, role: :owner)
    devlog = Post::Devlog.new(body: "work log", duration_seconds: minutes * 60)
    devlog.uploading_attachments = true
    devlog.save!
    Post.create!(project: project, user: user, postable: devlog)

    ship = Post::ShipEvent.new(body: "ship it", created_at: at, certification_status: "approved")
    ship.uploading_attachments = true
    ship.save!
    Post.create!(project: project, user: user, postable: ship, created_at: at)

    review = Certification::Ysws.create!(user: user, project: project, post_ship_event: ship,
                                        original_minutes: minutes, reviewed_at: reviewed_at)
    Certification::Devlog.create!(post_devlog: devlog, ysws_review: review, original_minutes: minutes,
                                  approved_minutes: approved, status: approved.positive? ? :approved : :rejected)
    review
  end
end
