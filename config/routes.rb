class AdminConstraint
  def self.matches?(request)
    # otherwise admins who impersonated non admins can't stop
    if request.path == "/admin/users/stop_impersonating" && request.session[:impersonator_user_id].present?
      user = User.find_by(id: request.session[:impersonator_user_id])
    else
      user = admin_user_for(request)
    end

    return false unless user

    policy = AdminPolicy.new(user, :admin)
    # Allow admins, fraud dept, and fulfillment persons (who have limited access)
    policy.access_admin_endpoints? ||
      policy.access_fulfillment_view? ||
      (request.path == "/admin/flavortime_dashboard" && policy.access_flavortime_dashboard?)
  end

  def self.admin_user_for(request)
    user = User.find_by(id: request.session[:user_id])
    return user if user

    if Rails.env.development? && ENV["DEV_ADMIN_USER_ID"].present?
      User.find_by(id: ENV["DEV_ADMIN_USER_ID"])
    end
  end

  def self.allow?(request, permission)
    user = admin_user_for(request)
    user && AdminPolicy.new(user, :admin).public_send(permission)
  end
end

class HelperConstraint
  def self.matches?(request)
    u = User.find_by(id: request.session[:user_id])
    u ||= User.find_by(id: ENV["DEV_ADMIN_USER_ID"]) if Rails.env.development?
    u && HelperPolicy.new(u, :helper).access?
  end
end

Rails.application.routes.draw do
  # Sitemap
  get "sitemap.xml", to: "sitemaps#index", as: :sitemap, defaults: { format: :xml }

  # Static OG images
  get "og/:page", to: "og_images#show", as: :og_image, defaults: { format: :png }
  # Landing
  root "landing#index"
  # get "marketing", to: "landing#marketing"

  # RSVPs
  resources :rsvps, only: [ :create ]
  get "rsvps/confirm/:token", to: "rsvps#confirm", as: :confirm_rsvp
  get "tic_tac", to: "rsvps#tic_tac", as: :tic_tac, defaults: { format: :text }

  # Shop
  get "shop", to: "shop#index"
  get "shop/my_orders", to: "shop#my_orders"
  delete "shop/cancel_order/:order_id", to: "shop#cancel_order", as: :cancel_shop_order
  get "shop/order", to: "shop#order"
  post "shop/order", to: "shop#create_order"
  patch "shop/update_region", to: "shop#update_region"
  resources :shop_suggestions, only: [ :create ]

  # Report Reviews
  get "report-reviews/review/:token", to: "report_reviews#review", as: :review_report_token
  get "report-reviews/dismiss/:token", to: "report_reviews#dismiss", as: :dismiss_report_token

  # Voting
  resources :votes, only: [ :new, :create, :index ] do
    collection do
      post :skip
    end
  end

  # Explore
  get "explore", to: "explore#index", as: :explore_index
  get "explore/gallery", to: "explore#gallery", as: :explore_gallery
  get "explore/following", to: "explore#following", as: :explore_following
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Test error page for Sentry
  get "test_error" => "debug#error" unless Rails.env.production?

  # Letter opener web for development email preview
  if Rails.env.development?
    mount LetterOpenerWeb::Engine, at: "/letter_opener"

    get "og_image_previews", to: "og_image_previews#index"
    get "og_image_previews/*id", to: "og_image_previews#show", as: :og_image_preview

  end

  # Action Mailbox for incoming HCB and tracking emails
  mount ActionMailbox::Engine => "/rails/action_mailbox"
  mount ActiveInsights::Engine => "/insights"

  # hackatime should not create a new session; it's used for linking
  get "auth/hackatime/callback", to: "identities#hackatime"

  # Sessions
  get "auth/:provider/callback", to: "sessions#create"
  get "/auth/failure", to: "sessions#failure"
  delete "logout", to: "sessions#destroy"
  get "dev_login", to: "sessions#dev_login", as: :dev_login_auto if Rails.env.development?
  get "dev_login/:id", to: "sessions#dev_login", as: :dev_login if Rails.env.development?

  # OAuth callback for HCA
  # get "/oauth/callback", to: "sessions#create"

  # Kitchen
  get "kitchen", to: "kitchen#index"

  # Leaderboard
  get "leaderboard", to: "leaderboard#index"

  # My
  get "my/balance", to: "my#balance", as: :my_balance
  patch "my/settings", to: "my#update_settings", as: :my_settings
  post "my/cookie_click", to: "my#cookie_click", as: :my_cookie_click
  post "my/dismiss_thing", to: "my#dismiss_thing", as: :dismiss_thing
  delete "my/club", to: "my#unlink_club", as: :my_club
  get "my/achievements", to: "achievements#index", as: :my_achievements

  namespace :seller do
    resources :orders, only: %i[index show] do
      member do
        post :reveal_address
        post :mark_fulfilled
      end
    end
  end

  namespace :user, path: "" do
    resources :tutorial_steps, only: [ :show ] do
      member do
        post :complete
      end
    end
  end

  namespace :helper, constraints: HelperConstraint do
    root to: "application#index"
    resources :users, only: [ :index, :show ] do
      member do
        get :balance
      end
    end
    resources :projects, only: [ :index, :show ] do
      member do
        post :restore
      end
    end
    resources :shop_orders, only: [ :index, :show ]
    resources :support_vibes, only: [ :index ]
  end

  # admin shallow routing
  namespace :admin, constraints: AdminConstraint do
    root to: "application#index"

    mount Blazer::Engine, at: "blazer", constraints: ->(request) {
      AdminConstraint.allow?(request, :access_blazer?)
    }

    mount Flipper::UI.app(Flipper), at: "flipper", constraints: ->(request) {
      AdminConstraint.allow?(request, :access_flipper?)
    }

    mount MissionControl::Jobs::Engine, at: "jobs", constraints: ->(request) {
      AdminConstraint.allow?(request, :access_jobs?)
    }

    resources :users, only: [ :index, :show, :update ], shallow: true do
       member do
         post :promote_role
         post :demote_role
         post :toggle_flipper
         post :sync_hackatime
         post :mass_reject_orders
         post :adjust_balance
         post :ban
         post :unban
         post :cancel_all_hcb_grants
         post :impersonate
         post :refresh_verification
         post :toggle_voting_lock
         get  :votes
         post :set_vote_balance
         patch :set_ysws_eligible_override
       end
       collection do
         post :stop_impersonating
       end
     end
    resources :projects, only: [ :index, :show ], shallow: true do
      member do
        post :restore
        post :delete
        post :update_ship_status
        post :force_state
        get  :votes
      end
    end
    get "user-perms", to: "users#user_perms"
    get "manage-shop", to: "shop#index"
    post "shop/clear-carousel-cache", to: "shop#clear_carousel_cache", as: :clear_carousel_cache
    resources :shop_items, only: [ :new, :create, :show, :edit, :update, :destroy ] do
      collection do
        post :preview_markdown
      end
      member do
        post :request_approval
      end
    end
    resources :shop_orders, only: [ :index, :show ] do
      member do
        post :reveal_address
        post :reveal_phone
        post :approve
        post :review_order
        post :reject
        post :place_on_hold
        post :release_from_hold
        post :mark_fulfilled
        post :update_internal_notes
        post :assign_user
        post :cancel_hcb_grant
        post :refresh_verification
        post :send_to_theseus
        post :approve_verification_call
        post :force_state
      end
    end
    resources :shop_suggestions, only: [ :index ] do
      member do
        post :dismiss
        post :disable_for_user
      end
    end
    resources :special_activities, only: [ :index, :create ] do
      member do
        post :toggle_payout
        post :mark_winner
      end
      collection do
        post :give_payout
        post :mark_payout_given
        post :toggle_live
      end
    end
    resources :messages, only: [ :index, :create ]
    resources :support_vibes, only: [ :index, :create ]
    resources :sw_vibes, only: [ :index ]
    resources :suspicious_votes, only: [ :index ]
    resources :audit_logs, only: [ :index, :show ]
    resources :reports, only: [ :index, :show ] do
      collection do
        post :process_demo_broken
      end
      member do
        post :review
        post :dismiss
      end
    end
    get "payouts_dashboard", to: "payouts_dashboard#index"
    get "fraud_dashboard", to: "fraud_dashboard#index"
    get "voting_dashboard", to: "voting_dashboard#index"
    get "vote_spam_dashboard", to: "vote_spam_dashboard#index"
    get "vote_spam_dashboard/users/:user_id", to: "vote_spam_dashboard#show", as: :vote_spam_dashboard_user
    get "vote_quality_dashboard", to: "vote_quality_dashboard#index"
    get "vote_quality_dashboard/users/:user_id", to: "vote_quality_dashboard#show", as: :vote_quality_dashboard_user
    get "ship_event_scores", to: "ship_event_scores#index"
    get "super_mega_dashboard", to: "super_mega_dashboard#index"
    delete "super_mega_dashboard/clear_cache", to: "super_mega_dashboard#clear_cache", as: :super_mega_dashboard_clear_cache
    get "flavortime_dashboard", to: "flavortime_dashboard#index"
    get "super_mega_dashboard/load_section", to: "super_mega_dashboard#load_section"
    post "super_mega_dashboard/refresh_nps_vibes", to: "super_mega_dashboard#refresh_nps_vibes", as: :super_mega_dashboard_refresh_nps_vibes
    resources :fulfillment_dashboard, only: [ :index ] do
      collection do
        post :send_letter_mail
      end
    end
    resources :fulfillment_payouts, only: [ :index, :show ] do
      member do
        post :approve
        post :reject
      end
      collection do
        post :trigger
      end
    end
  end

  get "queue", to: "queue#index"

  # Project Ideas
  post "project_ideas/random", to: "project_ideas#random", as: :random_project_ideas

  # Projects
  resources :projects, shallow: true do
    resources :memberships, only: [ :create, :destroy ], module: :projects
    resources :devlogs, only: %i[new create edit update destroy], module: :projects, shallow: false do
      member do
        get :versions
      end
    end
    resources :reports, only: [ :create ], module: :projects
    resource :og_image, only: [ :show ], module: :projects, defaults: { format: :png }
    resource :ships, only: [ :new, :create ], module: :projects
    member do
      get :readme
      get :lapse_timelapses
      get :stats
      post :mark_fire
      post :unmark_fire
      post :follow
      delete :unfollow
    end
  end

  # Devlog likes and comments
  resources :devlogs, only: [] do
    resource :like, only: [ :create, :destroy ]
    resources :comments, only: [ :create, :destroy ]
  end

  # Public user profiles
  resources :users, only: [ :show ] do
    resource :og_image, only: [ :show ], module: :users, defaults: { format: :png }
    member do
      get :stats
    end
  end

  get "edu", to: "landing#edu", as: :edu

  get "/:ref", to: "landing#index", constraints: { ref: /[a-z0-9][a-z0-9_-]{0,63}/ }
end
