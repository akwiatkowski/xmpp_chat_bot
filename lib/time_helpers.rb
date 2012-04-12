class Time
  def to_s_timedate
    "#{self.to_s_date} #{self.to_s_time}"
  end

  def to_s_time
    self.strftime("%H:%M")
  end

  def to_s_date
    self.strftime("%H:%M")
  end
end