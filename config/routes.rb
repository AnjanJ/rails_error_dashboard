RailsErrorDashboard::Engine.routes.draw do
  root to: "errors#index"

  resources :errors, only: [ :index, :show ] do
    member do
      post :resolve
    end
    collection do
      get :analytics
    end
  end
end
