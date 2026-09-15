class Admin::Certification::BannedFundingGrantsController < Admin::Certification::ApplicationController
  before_action :set_funding_request, only: :cancel_grant

  # Approved funding requests that paid an HCB grant to a recipient who is now
  # banned. The list a fraud admin works through to claw the money back.
  def index
    authorize ::Certification::FundingRequest, :banned_grants?
    @funding_requests = ::Certification::FundingRequest
      .with_banned_owner_grant
      .includes(:project, :user)
      .order(decided_at: :desc)
  end

  # Cancels the HCB card grant behind one funding request and marks the request
  # reversed so it drops off the report. Doesn't rewind the verdict or the
  # project stage — the full reversal lives in the `undo` flow; this is a
  # targeted money claw-back.
  def cancel_grant
    authorize @funding_request, :cancel_banned_grant?
    hashid = @funding_request.hcb_grant_hashid

    if hashid.blank?
      redirect_to admin_certification_banned_funding_grants_path,
                  alert: "That funding request has no active HCB grant to cancel."
      return
    end

    HCBService.cancel_card_grant!(hashid: hashid)
    # update_column (not update!) on purpose: it skips the after_save_commit
    # that would otherwise see a blank hashid and try to re-issue the grant, and
    # avoids re-running verdict callbacks. The hashid is kept as a record of what
    # was cancelled; `reversed_at` is what takes the row off the report. The
    # PaperTrail::Version below is the accessible audit trail for the money move.
    @funding_request.update_column(:reversed_at, Time.current)

    ::PaperTrail::Version.create!(
      item_type: "Certification::FundingRequest",
      item_id: @funding_request.id,
      event: "hcb_grant_canceled",
      whodunnit: user_for_paper_trail.to_s,
      object_changes: {
        hcb_grant_hashid: hashid,
        amount_cents: @funding_request.final_amount_cents,
        project_id: @funding_request.project_id,
        owner_id: @funding_request.owner&.id,
        reason: "recipient banned",
        canceled_by: current_user.display_name
      }.to_json
    )

    redirect_to admin_certification_banned_funding_grants_path,
                notice: "Canceled the $#{@funding_request.final_amount_dollars} HCB grant for “#{@funding_request.project.title}.”"
  rescue Pundit::NotAuthorizedError
    raise
  rescue StandardError => e
    Rails.logger.error "[BannedFundingGrants#cancel_grant] fr=#{params[:id]} #{e.class}: #{e.message}"
    redirect_to admin_certification_banned_funding_grants_path,
                alert: "Couldn't cancel the grant: #{e.message}"
  end

  private

  def set_funding_request
    @funding_request = ::Certification::FundingRequest.find(params[:id])
  end
end
