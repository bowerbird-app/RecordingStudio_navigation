# frozen_string_literal: true

class CreateRecordingStudioNavigationPages < ActiveRecord::Migration[8.1]
  def change
    create_table :recording_studio_navigation_pages, id: :uuid do |t|
      t.uuid :workspace_id, null: false
      t.string :title, null: false
      t.string :slug, null: false
      t.jsonb :content, default: {}, null: false
      t.boolean :published, default: false, null: false

      t.timestamps
    end

    add_page_indexes
  end

  private

  def add_page_indexes
    add_index :recording_studio_navigation_pages, :workspace_id
    add_index :recording_studio_navigation_pages, %i[workspace_id slug], unique: true
    add_index :recording_studio_navigation_pages, :published
  end
end
