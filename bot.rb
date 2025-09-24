require 'rubygems'
require 'bundler/setup'
Bundler.require(:default)
require 'telegram/bot'
require 'net/http'
require 'mini_magick'
require 'faraday'

Watir.default_timeout = 60

class Bot
  attr_reader :link, :browser, :client, :current_time
  PASS_CAPTCHA_ATTEMPTS_LIMIT = 5

  def initialize
    @link = "http://#{ENV.fetch('KDMID_SUBDOMAIN')}.kdmid.ru/queue/OrderInfo.aspx?id=#{ENV.fetch('ORDER_ID')}&cd=#{ENV.fetch('CODE')}"
    @client = TwoCaptcha.new(ENV.fetch('TWO_CAPTCHA_KEY'))
    @current_time = Time.now.utc.to_s
    puts 'Init...'

    options = {
      accept_insecure_certs: true,
    }
    if ENV['BROWSER_PROFILE']
      options.merge!(profile: ENV['BROWSER_PROFILE'])
    end
    @browser = Watir::Browser.new(
      ENV.fetch('BROWSER').to_sym,
      url: "http://#{ENV.fetch('HUB_HOST')}/wd/hub",
      options: options
    )

    # Ensure the browser is closed when the script exits
    at_exit do
      begin
        if @browser && @browser.exists?
          @browser.close
          puts "Browser closed successfully."
        else
          puts "Browser was not open or already closed."
        end
      rescue => e
        puts "Error closing browser: #{e.message}"
      end
    end    
  end

  def notify_user(message, photo_path = nil)
    return unless ENV['TELEGRAM_TOKEN'] && ENV['TELEGRAM_CHAT_ID']
  
    Telegram::Bot::Client.run(ENV['TELEGRAM_TOKEN']) do |bot|
      if photo_path
        bot.api.send_photo(
          chat_id: ENV['TELEGRAM_CHAT_ID'],
          photo: Faraday::UploadIO.new(photo_path, 'image/png'),
          caption: message,
          parse_mode: 'Markdown'
        )
      else
        bot.api.send_message(
          chat_id: ENV['TELEGRAM_CHAT_ID'],
          text: message,
          parse_mode: 'Markdown'
        )
      end
    end
  rescue => e
    puts "Error sending message to Telegram: #{e.message}"
  end


  def send_scr(photo_path)
    return unless ENV['TELEGRAM_TOKEN']
  
    Telegram::Bot::Client.run(ENV['TELEGRAM_TOKEN']) do |bot|
      bot.api.send_photo(chat_id: ENV['TELEGRAM_CHAT_ID'], photo: Faraday::UploadIO.new(photo_path, 'image/png'))
    end
  end
  

  def pass_hcaptcha
    sleep 5

    return unless browser.div(id: 'h-captcha').exists?

    sitekey = browser.div(id: 'h-captcha').attribute_value('data-sitekey')
    puts "sitekey: #{sitekey} url: #{browser.url}"

    captcha = client.decode_hcaptcha!(sitekey: sitekey, pageurl: browser.url)
    captcha_response = captcha.text
    puts "captcha_response: #{captcha_response}"

    3.times do |i|
      puts "attempt: #{i}"
      sleep 2
      ['h-captcha-response', 'g-recaptcha-response'].each do |el_name|
        browser.execute_script(
          "document.getElementsByName('#{el_name}')[0].style = '';
           document.getElementsByName('#{el_name}')[0].innerHTML = '#{captcha_response.strip}';
           document.querySelector('iframe').setAttribute('data-hcaptcha-response', '#{captcha_response.strip}');"
        )
      end
      sleep 3
      browser.execute_script("cb();")
      sleep 3
      break unless browser.div(id: 'h-captcha').exists?
    end

    if browser.alert.exists?
      browser.alert.ok
    end
  end

  def pass_ddgcaptcha
    attempt = 1
    sleep 5

    while browser.div(id: 'ddg-captcha').exists? && attempt <= PASS_CAPTCHA_ATTEMPTS_LIMIT
      puts "attempt: [#{attempt}] let's find the ddg captcha image..."

      checkbox = browser.div(id: 'ddg-captcha')
      checkbox.wait_until(timeout: 60, &:exists?)
      checkbox.click

      captcha_image = browser.iframe(id: 'ddg-iframe').images(class: 'ddg-modal__captcha-image').first
      captcha_image.wait_until(timeout: 5, &:exists?)

      puts 'save captcha image to file...'
      sleep 3
      image_filepath = "./captches/#{current_time}.png"
      base64_to_file(captcha_image.src, image_filepath)

      puts 'decode captcha...'
      captcha = client.decode!(path: image_filepath)
      captcha_code = captcha.text
      puts "captcha_code: #{captcha_code}"

      # puts 'Enter code:'
      # code = gets
      # puts code

      text_field = browser.iframe(id: 'ddg-iframe').text_field(class: 'ddg-modal__input')
      text_field.set captcha_code
      browser.iframe(id: 'ddg-iframe').button(class: 'ddg-modal__submit').click

      attempt += 1
      sleep 15
    end
  end

  def base64_to_file(base64_data, filename=nil)
    start_regex = /data:image\/[a-z]{3,4};base64,/
    filename ||= SecureRandom.hex

    regex_result = start_regex.match(base64_data)
    start = regex_result.to_s

    File.open(filename, 'wb') do |file|
      file.write(Base64.decode64(base64_data[start.length..-1]))
    end
  end

  def report_captcha(captcha_id, is_correct)
    action = is_correct ? 'reportgood' : 'reportbad'
    uri = URI("http://2captcha.com/res.php?key=#{ENV['TWO_CAPTCHA_KEY']}&action=#{action}&id=#{captcha_id}")
    Net::HTTP.get(uri)
  end

  def pass_captcha_on_form_and_report
    incorrect_attempts = 0
    max_attempts = ENV.fetch('MAX_INCORRECT_ATTEMPTS', 15).to_i
  
    loop do
      sleep 3
  
      if browser.alert.exists?
        browser.alert.ok
        puts 'alert found'
      end
  
      puts 'save browser image to file...'
      image_filepath = "./screenshots/#{current_time}.png"
      browser_image = browser.screenshot.save(image_filepath)


      puts 'crop captcha from screenshot'
      captcha_path =  "./captches/#{current_time}.png"
      image = MiniMagick::Image.open(image_filepath)

      # Проверка размеров перед обрезкой
      if image.width >= 773 && image.height >= 685
        puts 'crop captcha from screenshot'
        captcha_image = image.crop('256x256+517+429')
        image.write(captcha_path)
      else
        puts 'Unexpected image size, skipping crop'
        FileUtils.cp(image_filepath, captcha_path)
      end

  
      puts 'decode captcha...'
      captcha = client.decode!(path: captcha_path)
      captcha_code = captcha.text
      captcha_id = captcha.id
      puts "captcha_code: #{captcha_code}"
  
      text_field = browser.text_field(id: 'ctl00_MainContent_txtCode')
      text_field.set captcha_code
      browser.button(id: 'ctl00_MainContent_ButtonA').click
  
      sleep 3 # Wait for the page to process captcha
  
      if browser.text.include?('Символы с картинки введены не правильно')
        report_captcha(captcha_id, false)
        incorrect_attempts += 1
        puts "Captcha was solved incorrectly, attempt #{incorrect_attempts}"
        if incorrect_attempts >= max_attempts
          puts "Reached maximum incorrect attempts (#{max_attempts}), sleeping for 1 hour..."
          notify_user('Reached maximum incorrect attempts! Sleeping for 1 hour...')
          sleep 3600 # Sleep for 1 hour
          incorrect_attempts = 0 # Reset attempts after sleep
        end
        next # Retry captcha solving
      else
        puts "Captcha was solved at attempt #{incorrect_attempts}!"
        report_captcha(captcha_id, true)
        break # Exit loop if captcha solved correctly
      end
    end
  end
  

def click_make_appointment_button
  content_element = browser.span(id: 'ctl00_MainContent_Content')
  content_text = content_element.text
  notify_user("*Проверка:*\n\n#{content_text}")

  make_appointment_btn = browser.button(id: 'ctl00_MainContent_ButtonB')
  make_appointment_btn.wait_until(timeout: 60, &:exists?)
  make_appointment_btn.click
end

def save_page
  timestamp = current_time
  screenshot_path = "./screenshots/#{timestamp}.png"
  html_path = "./pages/#{timestamp}.html"
  browser.screenshot.save(screenshot_path)
  File.write(html_path, browser.html)
  [screenshot_path, html_path]
end

def appointment_available?
  !browser.p(text: /нет свободного времени/).exists?
end

def web_error_detected?
  browser.div(class: 'error-class').exists? ||
    browser.p(xpath: ".//*[local-name()='p'][contains(normalize-space(), 'Bad')]").exists?
end

def stop_text_found?
  failure_texts = [
    'Извините, но в настоящий момент',
    'Свободное время в системе записи отсутствует',
    'Для проверки наличия свободного времени',
    'нет свободного времени',
    'Bad Gateway'
  ]
  failure_texts.any? { |text| browser.text.include?(text) }
end

def get_center_panel_text
  panel = browser.td(id: 'center-panel')
  panel.wait_until(timeout: 10, &:exists?)
  panel.text.to_s
rescue
  ''
end


def notify_user_about_appointment(panel_text, screenshot_path)
  nlocation = ENV['KDMID_SUBDOMAIN']
  puts "Notifying user about appointment with screenshot"
  notify_user("✅ New time for an appointment found in #{nlocation}!\n\n#{panel_text}", screenshot_path)
end

def handle_exception(e)
  puts "Exception occurred: #{e.message}"
  if ENV['SEND_EXCEPTION'] == 'true'
    begin
      notify_user("⚠️ Exception occurred: #{e.message}")
    rescue => notify_err
      puts "Failed to send exception notification to Telegram: #{notify_err.message}"
    end
  end
end

def check_queue
  puts "===== Current time: #{current_time} ====="
  begin
    browser.goto link

    pass_hcaptcha
    pass_ddgcaptcha

    browser.button(id: 'ctl00_MainContent_ButtonA').wait_until(timeout: 30, &:exists?)
    pass_captcha_on_form_and_report

    click_make_appointment_button

    panel_text = get_center_panel_text
    screenshot_path, _ = save_page

    if appointment_available? && !stop_text_found? && !web_error_detected?
      notify_user_about_appointment(panel_text, screenshot_path)
    else
      puts "No appointment available or error detected"
    end
  rescue Exception => e
    handle_exception(e)
    notify_user("*Мест нет!*\n\n#{get_center_panel_text}")
    raise e
  ensure
    browser.close
    puts '=' * 50
  end
end

Bot.new.check_queue