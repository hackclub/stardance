# The subject's stardust ledger, the same history they see on /my/balance,
# loaded into the fraud page on demand rather than with every review.
class Admin::Fraud::Subjects::BalancesController < Admin::ApplicationController
  ENTRIES_PER_PAGE = 25

  def show
    @user = User.find(params[:subject_id])
    authorize :fraud_subject, policy_class: Admin::FraudSubjectPolicy

    @pagy, @entries = pagy(
      @user.ledger_entries.includes(:ledgerable).order(created_at: :desc),
      limit: ENTRIES_PER_PAGE
    )

    render layout: false
  end
end
