module Edition::ScheduledPublishing
  extend ActiveSupport::Concern

  included do
    validate :scheduled_publication_is_in_the_future, if: :scheduled_publication_must_be_in_the_future?
  end

  module ClassMethods
    def scheduled_publishing_robot
      User.where(name: "Scheduled Publishing Robot", uid: nil).first || create_scheduled_publishing_robot
    end

    def publish_all_due_editions_as(user, logger = Rails.logger)
      Whitehall.stats_collector.increment("scheduled_publishing.call_rate")
      Whitehall.stats_collector.gauge("scheduled_publishing.due", due_for_publication.count)
      due_for_publication.shuffle.each do |edition|
        publish_atomically_as(user, edition.id, logger)
      end
      Whitehall.stats_collector.gauge("scheduled_publishing.due", due_for_publication.reload.count)
    end

    def due_for_publication
      scheduled.where(arel_table[:scheduled_publication].lteq(Time.zone.now))
    end

  private
    def create_scheduled_publishing_robot
      permissions = {
        GDS::SSO::Config.default_scope => [
          User::Permissions::SIGNIN,
          User::Permissions::PUBLISH_SCHEDULED_EDITIONS
        ]
      }
      User.create!(name: "Scheduled Publishing Robot", uid: nil) do |user|
        user.permissions = permissions
      end
    end

    def publish_atomically_as(user, edition_id, logger = Rails.logger)
      acting_as(user) do
        Edition.connection.execute "set transaction isolation level serializable"
        Edition.connection.transaction do
          edition = Edition.find(edition_id)
          if edition.publish_as(user)
            Whitehall.stats_collector.increment("scheduled_publishing.published")
            logger.info("Published #{edition.title} automatically")
            return true
          else
            logger.error("Unable to publish edition id '#{edition_id}' because '#{edition.errors.full_messages.to_sentence}'")
            return false
          end
        end
      end
    rescue => e
      logger.error("Unable to publish edition id '#{edition_id}' because '#{e}'")
      false
    end

    def acting_as(user)
      original_user = PaperTrail.whodunnit
      PaperTrail.whodunnit = user
      yield
    ensure
      PaperTrail.whodunnit = original_user
    end
  end

  module InstanceMethods

    def schedulable_by?(user, options = {})
      reason_to_prevent_scheduling_by(user, options).nil?
    end

    def reason_to_prevent_scheduling_by(user, options = {})
      if scheduled?
        "This edition is already scheduled for publication"
      else
        reason_to_prevent_approval_by(user, options) or if scheduled_publication.blank?
          "This edition does not have a scheduled publication date set"
        end
      end
    end

    def schedule_as(user, options = {})
      if schedulable_by?(user, options)
        self.force_published = options[:force]
        schedule!
        true
      else
        errors.add(:base, reason_to_prevent_scheduling_by(user, options))
        false
      end
    end

    def unschedulable_by?(user)
      reason_to_prevent_unscheduling_by(user).nil?
    end

    def reason_to_prevent_unscheduling_by(user)
      if !scheduled?
        "This edition is not scheduled for publication"
      end
    end

    def unschedule_as(user)
      if unschedulable_by?(user)
        self.force_published = false
        unschedule!
        true
      else
        errors.add(:base, reason_to_prevent_unscheduling_by(user))
        false
      end
    end

    def reason_to_prevent_publication_by(user, options = {})
      if scheduled?
        if Time.zone.now < scheduled_publication
          "This edition is scheduled for publication on #{scheduled_publication.to_s}, and may not be published before"
        elsif !valid?
          "Can't publish invalid scheduled publication"
        elsif !user.can_publish_scheduled_editions?
          "User must have permission to publish scheduled publications"
        end
      elsif scheduled_publication.present?
        "Can't publish this edition immediately as it has a scheduled publication date. Schedule it for publication or remove the scheduled publication date."
      else
        super
      end
    end

    private

    def scheduled_publication_is_in_the_future
      if scheduled_publication.present? && scheduled_publication < Whitehall.default_cache_max_age.from_now
        errors[:scheduled_publication] << "date must be at least #{Whitehall.default_cache_max_age / 60} minutes from now"
      end
    end

    def scheduled_publication_must_be_in_the_future?
      draft? || submitted? || (state_was == 'rejected' && rejected?)
    end
  end
end
