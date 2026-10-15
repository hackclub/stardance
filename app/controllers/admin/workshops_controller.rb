class Admin::WorkshopsController < Admin::ApplicationController
  before_action -> { authorize :admin, :access_workshops? }
  before_action :set_workshop, only: [ :show, :edit, :update, :destroy ]
  # Casts the form's zone-less datetime strings as Eastern time. Wraps the
  # whole action because attribute casting runs lazily at save, not assignment.
  around_action :use_eastern_time, only: [ :create, :update ]

  def index
    @upcoming_workshops = Workshop.upcoming
    @past_workshops = Workshop.past
    @rsvp_counts = Workshop::Rsvp.group(:workshop_id).count
    @attendance_counts = Workshop::Attendance.group(:workshop_id).count
  end

  def show
    @rsvps = @workshop.rsvps.includes(:user).order(created_at: :asc)
    @attendances = @workshop.attendances.includes(:user).order(created_at: :asc)
  end

  def new
    @workshop = Workshop.new
  end

  def create
    @workshop = Workshop.new(workshop_params)
    if @workshop.save
      redirect_to admin_workshop_path(@workshop), notice: "Workshop created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @workshop.update(workshop_params)
      redirect_to admin_workshop_path(@workshop), notice: "Workshop updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @workshop.destroy!
    redirect_to admin_workshops_path, notice: "Workshop deleted."
  end

  private

    def set_workshop
      @workshop = Workshop.find(params[:id])
    end

    def workshop_params
      params.require(:workshop).permit(:title, :description, :zoom_link, :starts_at, :ends_at)
    end

    def use_eastern_time(&block)
      Time.use_zone(Workshop::TIME_ZONE, &block)
    end
end
