# frozen_string_literal: true

InnoxLan::Engine.routes.draw do
  get "/assets/logo-white.png" => "assets#logo"
  get "/assets/mark-color.png" => "assets#mark"
  get "/assets/founder.png" => "assets#founder"
  get "/assets/mascot-board.png" => "assets#mascot_board"
  get "/assets/kezai-girl-v2.jpg" => "assets#kezai_girl"
  get "/assets/kezai-astronaut-v2.jpg" => "assets#kezai_astronaut"
  get "/assets/kezai-duo-v2.jpg" => "assets#kezai_duo"
  get "/assets/join.js" => "assets#script"
  get "/assets/manifest.webmanifest" => "assets#manifest"
  get "/assets/manifest-v2.webmanifest" => "assets#manifest"
  get "/assets/app-icon-192.png" => "assets#app_icon_192"
  get "/assets/app-icon-512.png" => "assets#app_icon_512"
  get "/assets/app-icon-v2-192.png" => "assets#app_icon_192"
  get "/assets/app-icon-v2-512.png" => "assets#app_icon_512"
  get "/account" => "registrations#account"
  get "/" => "registrations#new"
  post "/" => "registrations#create"
  post "/login" => "registrations#login"
end

Discourse::Application.routes.draw do
  mount ::InnoxLan::Engine, at: "/join"
  get "/mobile" => "innox_lan/registrations#new"
  get "/Innoxsz-Forum.apk" => "innox_lan/downloads#android"
  get "/Kezai-Community.apk" => "innox_lan/downloads#android"
  get "/Kezai-Community-v1.3.apk" => "innox_lan/downloads#android"
end
