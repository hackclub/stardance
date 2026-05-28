class Admin::Certification::ShipsController < Admin::Certification::ApplicationController
  before_action :release_other_claims, only: [ :index, :next, :claim ]
  before_action :set_ship, only: [ :show, :update, :claim ]

  def index
    authorize ::Certification::Ship
    @ships = policy_scope(::Certification::Ship)
               .pending
               .includes(:project, :reviewer)
               .order(claim_expires_at: :asc, created_at: :asc)
               .limit(50)
  end

  def show
    authorize @ship
  end

  def update
    authorize @ship
    if @ship.update(ship_params)
      redirect_to next_admin_certification_ships_path, notice: "Verdict recorded."
    else
      render :show, status: :unprocessable_entity
    end
  end

  def next
    authorize ::Certification::Ship
    skip_ids = parse_skip_ids
    candidate = ::Certification::Ship.next_eligible(current_user, skip_ids: skip_ids)
    if candidate.nil?
      redirect_to admin_certification_ships_path, notice: "Queue is empty." and return
    end
    claimed = ::Certification::Ship.atomic_claim!(candidate.id, current_user)
    if claimed
      redirect_to admin_certification_ship_path(claimed)
    else
      new_skip = (skip_ids + [ candidate.id ]).uniq
      redirect_to next_admin_certification_ships_path(skip: new_skip.join(","))
    end
  end

  def claim
    authorize @ship, :claim?
    claimed = ::Certification::Ship.atomic_claim!(@ship.id, current_user)
    if claimed
      redirect_to admin_certification_ship_path(claimed)
    else
      redirect_to admin_certification_ships_path, alert: "Couldn't claim that review — someone else got it."
    end
  end

  private

  def set_ship
    @ship = ::Certification::Ship.find(params[:id])
  end

  def release_other_claims
    ::Certification::Ship.release_all_for(current_user) if current_user.present?
  end

  def parse_skip_ids
    params[:skip].to_s.split(",").map(&:to_i).reject(&:zero?)
  end

  def ship_params
    params.require(:certification_ship).permit(:status, :feedback, :internal_reason)
  end
end
