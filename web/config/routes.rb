Rails.application.routes.draw do
  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # Authentication
  get "login", to: "sessions#new", as: :login
  post "login", to: "sessions#create_from_password", as: :password_login
  get "auth/:provider/callback", to: "sessions#create"
  get "auth/failure", to: "sessions#failure"
  delete "logout", to: "sessions#destroy", as: :logout

  # Password management
  resource :password, only: [ :edit, :update ]

  # API documentation
  get "api/docs", to: "api_docs#index", as: :api_docs

  # Notes
  resources :notes do
    member do
      patch :restore
      patch :archive
      patch :unarchive
      patch :toggle_pin
      post :duplicate
      post :merge
      get :export
    end

    collection do
      get :search
      get :trash
      post :bulk_export
    end

    # Nested resources
    resources :shares, only: [ :create, :destroy ]
    resources :note_versions, only: [ :index, :show ], path: "versions" do
      member do
        post :restore
      end
    end
    resources :attachments, only: [ :create, :destroy ]
  end

  resources :tags, except: [ :show, :new ]

  # Admin
  get "admin", to: "admin#dashboard", as: :admin_dashboard
  patch "admin/users/:id", to: "admin#update_user", as: :admin_update_user
  delete "admin/users/:id", to: "admin#destroy_user", as: :admin_destroy_user

  # API v1
  namespace :api do
    namespace :v1 do
      post "auth/token", to: "auth#create_token"
      post "auth/refresh", to: "auth#refresh_token"

      resources :notes do
        member do
          patch :restore
          patch :archive
          patch :unarchive
          patch :toggle_pin
          post :duplicate
          post :merge
          get :export
        end
        collection do
          get :search
          get :trash
          post :bulk_export
        end
        resources :shares, only: [ :index, :create, :destroy ]
        resources :versions, only: [ :index, :show ], controller: "note_versions" do
          member do
            post :restore
          end
        end
        resources :attachments, only: [ :index, :create, :destroy ]
      end

      resources :tags, except: [ :new, :edit ]
    end
  end

  # Root
  root "notes#index"
end
