RailsErrorDashboard::Engine.routes.draw do
  root to: "errors#overview"

  # Dashboard overview
  get "overview", to: "errors#overview", as: :overview

  # Settings page
  get "settings", to: "errors#settings", as: :settings

  # Webhook endpoint for two-way issue sync (GitHub/GitLab/Codeberg)
  post "webhooks/:provider", to: "webhooks#receive", as: :webhook

  resources :errors, only: [ :index, :show ] do
    member do
      post :resolve
      post :assign
      post :unassign
      post :update_priority
      post :snooze
      post :unsnooze
      post :mute
      post :unmute
      post :update_status
      post :create_issue
      post :link_issue
    end
    collection do
      get :analytics
      get :platform_comparison
      get :correlation
      get :deprecations
      get :n_plus_one_summary
      get :cache_health_summary
      get :job_health_summary
      get :database_health_summary
      get :swallowed_exceptions
      get :rack_attack_summary
      get :actioncable_health_summary
      get :activestorage_health_summary
      get :releases
      get :diagnostic_dumps
      post :create_diagnostic_dump
      post :enable_coverage
      post :disable_coverage
      post :batch_action
    end
  end
end
