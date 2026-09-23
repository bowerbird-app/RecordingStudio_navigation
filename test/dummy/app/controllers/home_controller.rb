class HomeController < ApplicationController
  NAVIGATION_FILTERS = {
    "all" => "All",
    "admin" => "Admin",
    "sensitive" => "Sensitive"
  }.freeze

  def index
    @navigation_filters = NAVIGATION_FILTERS
    @navigation_filter = NAVIGATION_FILTERS.key?(params[:filter]) ? params[:filter] : "all"
    @destinations = destinations_for(@navigation_filter)
  end

  private

  def destinations_for(filter)
    case filter
    when "admin" then RecordingStudio::Navigation.destinations(tag: :admin)
    when "sensitive" then RecordingStudio::Navigation.destinations(sensitivity: :sensitive)
    else RecordingStudio::Navigation.destinations
    end
  end
end
