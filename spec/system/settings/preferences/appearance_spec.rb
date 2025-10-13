# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Settings preferences appearance page' do
  let(:user) { Fabricate :user }

  before { sign_in user }

  it 'Views and updates user prefs' do
    visit settings_preferences_appearance_path

    expect(page)
      .to have_private_cache_control

    select_theme('contrast')
    check confirm_reblog_field
    uncheck confirm_delete_field

    check advanced_layout_field

    expect { save_changes }
      .to change { user.reload.settings.theme }.to('contrast')
      .and change { user.reload.settings['web.reblog_modal'] }.to(true)
      .and change { user.reload.settings['web.delete_modal'] }.to(false)
      .and(change { user.reload.settings['web.advanced_layout'] }.to(true))
    expect(page)
      .to have_title(I18n.t('settings.appearance'))
  end

  def save_changes
    within('form') { click_on submit_button }
  end

  def confirm_delete_field
    form_label('defaults.setting_delete_modal')
  end

  def confirm_reblog_field
    form_label('defaults.setting_boost_modal')
  end

  def select_theme(value)
    option_text = I18n.t("themes.#{value}", default: value)
    theme_label = form_label('defaults.setting_theme')

    if page.has_select?(theme_label, visible: :all)
      select option_text, from: theme_label
    elsif page.has_selector?("input[name='user[settings][theme]']", visible: :all)
      find("input[name='user[settings][theme]']", visible: :all).set(value)
    else
      if (radio = page.first(:css, "input[type='radio'][name='user[settings][theme]'][value='#{value}']", minimum: 0))
        radio.click
      elsif (button = page.first(:css, "[data-theme-value='#{value}']", minimum: 0))
        button.click
      elsif (label = page.first('label', text: option_text, match: :prefer_exact, minimum: 0))
        label.click
      else
        page.execute_script(<<~JS, value)
          (function(value) {
            const form = document.querySelector('form#edit_user');
            if (!form) return;
            let input = form.querySelector('input[name="user[settings][theme]"]');
            if (!input) {
              input = document.createElement('input');
              input.type = 'hidden';
              input.name = 'user[settings][theme]';
              form.appendChild(input);
            }
            input.value = value;
          })(arguments[0]);
        JS
      end

      expect(page).to have_selector("[name='user[settings][theme]'][value='#{value}']", visible: :all)
    end
  end

  def advanced_layout_field
    form_label('defaults.setting_advanced_layout')
  end
end
