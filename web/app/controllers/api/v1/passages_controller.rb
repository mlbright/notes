module Api
  module V1
    # Retrieval for agents: the Passages most relevant to a query, best first.
    class PassagesController < Api::BaseController
      class InvalidParameter < StandardError; end

      rescue_from InvalidParameter do |e|
        render json: { error: e.message }, status: :bad_request
      end

      def index
        if params[:q].blank?
          render json: { error: "Query parameter 'q' is required" }, status: :bad_request
          return
        end

        result = Retrieval.new(
          user: current_user,
          query: params[:q],
          tag: params[:tag].presence,
          archived: archived_param,
          updated_after: time_param(:updated_after),
          updated_before: time_param(:updated_before),
          limit: limit_param
        ).call

        render json: { ranking: result.ranking, passages: result.passages.map { |passage| passage_json(passage) } }
      end

      private

      def archived_param
        value = params[:archived].presence || "include"
        return value if Retrieval::ARCHIVED_OPTIONS.include?(value)

        raise InvalidParameter, "archived must be one of: #{Retrieval::ARCHIVED_OPTIONS.join(', ')}"
      end

      # Accepts an ISO 8601 date or date-time; a bare date means its start.
      def time_param(name)
        value = params[name].presence or return
        Time.zone.iso8601(value)
      rescue ArgumentError
        raise InvalidParameter, "#{name} must be an ISO 8601 date or date-time"
      end

      def limit_param
        return Retrieval::DEFAULT_LIMIT if params[:limit].blank?

        Integer(params[:limit], 10)
      rescue ArgumentError, TypeError
        raise InvalidParameter, "limit must be an integer"
      end

      def passage_json(passage)
        note = passage.note
        {
          text: passage.body,
          heading_trail: passage.heading_trail,
          note: {
            id: note.id,
            title: note.title,
            tags: note.tags.map(&:name).sort,
            created_at: note.created_at,
            updated_at: note.updated_at,
            archived: note.archived,
            owned: note.user_id == current_user.id,
            url: note_url(note)
          }
        }
      end
    end
  end
end
