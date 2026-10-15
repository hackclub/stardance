module Api
  # cc docs/privacy.md.
  class PrivacyController < ActionController::API
    before_action :authenticate!
    rescue_from Privacy::Eraser::DependencyUnavailable do
      PrivacyTokenUse.where(jti: @claims.jti).delete_all
      log("dependency_unavailable")
      render_error("dependency_unavailable", :service_unavailable)
    end

    def delete
      eraser = Privacy::Eraser.new(@claims.subject)
      if eraser.user_ids.any? && eraser.manual_review_required?
        log("manual_review_required")
        return render_error("manual_review_required", :conflict)
      end

      respond(eraser.call(dry_run: @claims.dry_run, request_id: @claims.request_id))
    end

    def export
      respond(Privacy::Eraser.new(@claims.subject).call(dry_run: true, request_id: @claims.request_id))
    end

    private

    def authenticate!
      @claims = Privacy::Token.verify!(request.authorization.to_s[/\ABearer (.+)\z/, 1])
      return render_error("action_mismatch", :bad_request) unless @claims.action == action_name

      render_error("replayed", :conflict) unless PrivacyTokenUse.record_first_use!(@claims.jti)
    rescue Privacy::Token::Invalid => e
      Rails.logger.info("privacy #{action_name} rejected error=#{e.code}")
      render_error(e.code, e.is_a?(Privacy::Token::Unavailable) ? :service_unavailable : :unauthorized)
    end

    def respond(result)
      log(result.found ? "found" : "not_found")
      render json: {
        request_id: @claims.request_id,
        found: result.found,
        dry_run: @claims.dry_run,
        deleted: result.deleted,
        retained: result.retained
      }
    end

    def log(outcome)
      Rails.logger.info("privacy #{action_name} request_id=#{@claims.request_id} dry_run=#{@claims.dry_run} outcome=#{outcome}")
    end

    def render_error(code, status)
      render json: { error: code }, status:
    end
  end
end
