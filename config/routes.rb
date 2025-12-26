RailsErrorDashboard::Engine.routes.draw do
  root to: "errors#overview"

  # Dashboard overview
  get "overview", to: "errors#overview", as: :overview

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
      post :batch_action
    end
  end
end
