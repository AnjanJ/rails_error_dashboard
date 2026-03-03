RailsErrorDashboard::Engine.routes.draw do
  root to: "errors#overview"

  # Dashboard overview
  get "overview", to: "errors#overview", as: :overview

  # Settings page
  get "settings", to: "errors#settings", as: :settings

  resources :errors, only: [ :index, :show ] do
    member do
      post :resolve
      post :assign
      post :unassign
      post :update_priority
      post :snooze
      post :unsnooze
      post :update_status
      post :add_comment
    end
    collection do
      get :analytics
      get :platform_comparison
      get :correlation
      get :deprecations
      get :n_plus_one_summary
      get :cache_health_summary
      post :batch_action
    end
  end
end
