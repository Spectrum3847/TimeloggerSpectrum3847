class User < ActiveRecord::Base
  before_save :lowercaseID
  before_save :encrypt_password
  before_save :clean_phone_number
  has_many :timelogs
  belongs_to :school
  has_and_belongs_to_many :forms
  has_many :forms_users
  has_many :years, :through=>:timelogs
  has_one :hour_override, -> {where(year_id: Year.current_year.id)}
  has_many :hour_exceptions, -> {where(year_id: Year.current_year.id)}

  # Setup accessible (or protected) attributes for your model
  #attr_accessible :school, :school_id, :email, :password, :password_confirmation, :name_first, :name_last, :phone,:location, :admin, :userid, :archive, :form_id, :form_ids, :forms_user_id, :gender, :graduation_year, :student_leader
  # attr_accessible :title, :body
  attr_accessor :password
  
  validates_format_of :email, :with => /\A([\w\.%\+\-]+)@([\w\-]+\.)+([\w]{2,})\z/i, :message=>"Please enter a valid email."
  validates_uniqueness_of :userid
  validates_confirmation_of :password
  validates_presence_of :password, :on => :create
  validates_presence_of :email
  validates_presence_of :userid
  validates_presence_of :gender
  validates_presence_of :location
  validates_uniqueness_of :email
  
  scope :archived, -> {where(:archive => true)}
  #scope :active, where("users.archive IS NOT 1") ##Change back for production!!!
  
  
  ###################### General Info ##########################
  def self.active
    where("users.archive IS NOT true")
  end
  def is_mentor
    if !self.school.nil? && self.school.name=="Mentor"
      return true
    end
    return false
  end
  def full_name
    return "#{self.name_first} #{self.name_last}"
  end
  def get_class
    if Year.current_year.nil?
      return "No year"
    end
    
    case
    when (Year.current_year.year_end.year + 3).to_s == self.graduation_year
      return "Freshman"
    when (Year.current_year.year_end.year + 2).to_s == self.graduation_year
      return "Sophomore"
    when (Year.current_year.year_end.year + 1).to_s == self.graduation_year
      return "Junior"
    when (Year.current_year.year_end.year).to_s == self.graduation_year
      return "Senior"
    end
  end
  ###################### END General Info ##########################
  ###################### Authentication ##########################
  def self.authenticate(email, password)
    #user = find_by_email(email)
    user = User.where(email: email).first
    if user && user.password_hash == BCrypt::Engine.hash_secret(password, user.password_salt)
      user
    else
      nil
    end
  end
  def encrypt_password
    if password.present?
      self.password_salt = BCrypt::Engine.generate_salt
      self.password_hash = BCrypt::Engine.hash_secret(password, password_salt)
    end
  end
  def signed_in
    if self.timelogs.in_today.nil? || self.timelogs.in_today.empty?
      return false
    else
      return self.timelogs.in_today.first
    end
  end
  ###################### END Authentication ##########################
  ######################Yearly Totals##########################
  def years_build_hours(year)
    #Number of build season hours for the year
    total = 0
    self.timelogs.build_season_hours(year).each do |log|
      total = total + log.time_logged
    end
    return total
  end
  def build_hours_formatted(seconds)
    #format the build season hours
    return User.format_time(years_build_hours(seconds))
  end
  def years_total_hours(year)
    total = 0
    self.timelogs.in_year(year).each do |log|
        total = total + log.time_logged
    end
    total
  end
  def total_hours_formatted(seconds)
    return User.format_time(years_total_hours(seconds))
  end
  def self.allStudentsForYear(year)
    users = User.joins(:timelogs).where("timein >= ? and timein < ?",year.year_start,year.year_end)
    return users
  end
  def has_hours(year)
    logs = self.timelogs.in_year(year)
    if logs.size > 0
      return true
    end
    return false
  end
  def preseason_meetings
    #Number of pre season meetings for the year
    return past_preseason_meetings(Year.current_year)
  end
  def past_preseason_meetings(year)
    #Number of pre season meetings for the year
    logs = self.timelogs.pre_season_hours(year)
    
    logs_grouped = logs.group_by{|a| a.timein.strftime("%m/%d/%Y")} rescue 0
    return logs_grouped.count rescue 0
  end
  ###################### END Yearly Totals##########################
  ###################### Logging/Formatting ##########################
  def self.format_time(total)
    time = Time.at(total).utc
    return "#{'%02d' % (time.hour + (time.day-1)*24)}:#{'%02d' % time.min}:#{'%02d' % time.sec}"
  end
  
  ###################### Requirements ##########################
  def all_forms_in
    users_forms = self.forms.map{|x| x.id}
    all_forms = Form.all_required.reject{|x| users_forms.include? x.id}
    if all_forms.empty?
      return true
    else
      return false
    end
  end
  ###################### Build Season ##########################
  def required_hours 
    if !self.hour_override.nil?
      return self.hour_override.hours_required
    end
    if self.student_leader
      return Constants::LEADERSHIP_HOURS
    end
    
    case self.get_class
    when "Freshman"
      return Constants::FRESHMAN_HOURS
    when "Sophomore"
      return Constants::SOPHOMORE_HOURS
    when "Junior"
      return Constants::JUNIOR_HOURS
    when "Senior"
      return Constants::SENIOR_HOURS
    end
    
    return 0
  end
  ###################### End Build Season ##########################
  
  
  private 
    def lowercaseID
      self.userid = self.userid.downcase
    end
    def clean_phone_number
      self.phone = self.phone.gsub(/\D/, '')
    end
end
