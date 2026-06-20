Raffle::Engine.routes.draw do
  root to: "dashboard#show"
  get "dashboard", to: "dashboard#show", as: :dashboard
  post "claim", to: "dashboard#claim", as: :claim

  match "auth/github/callback", to: "sessions#create", via: [ :get, :post ]
  get "auth/failure", to: "sessions#failure"
  delete "logout", to: "sessions#destroy", as: :logout

  if Rails.env.development? || Rails.env.test?
    get "dev_login(/:handle)", to: "sessions#dev_login", as: :dev_login
    post "dev/referrals", to: "dashboard#dev_referrals", as: :dev_referrals
  end

  match "*path", to: "application#not_found", via: :all, format: false
end
