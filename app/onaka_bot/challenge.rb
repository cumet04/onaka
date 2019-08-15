# frozen_string_literal: true

require './app/onaka_bot/base'
require './app/lib/i18n_settings'

module OnakaBot
  module Challenge
    extend Base

    def self.help
      I18n.t('modules.challenge.help.')
    end

    def self.exec(cmd, argv, user, current_time, data)
      return false unless cmd == 'challenge'

      target, bet = argv.take(2).map(&:to_i)
      challenge(user, current_time, data, { target: target, bet: bet }.compact)

      true
    end

    def self.challenge(user, current_time, data, target: nil, bet: nil)
      result = ActiveRecord::Base.transaction {
        current_stamina = user.stamina(current_time)

        bet ||= current_stamina
        target ||= bet * 2

        prob = bet.fdiv(target) # チャレンジ成功率

        if bet <= 0 || target <= bet
          # 賭けスタミナが範囲外 (0 < 賭けスタミナ < 目標スタミナ が満たされていない)
          {
            status: :out_of_range_bet,
            bet: bet,
            target: target,
            current_stamina: current_stamina,
          }
        else
          user.decrease_stamina!(current_time, bet)
          status = if rand < prob
            # チャレンジ成功
            user.increase_stamina!(current_time, target)
            :challenge_succeed
          else
            # チャレンジ失敗
            :challenge_failed
          end

          {
            status: status,
            bet: bet,
            target: target,
            current_stamina: current_stamina,
            prob: prob,
            result: user.stamina(current_time),
          }
        end
      }

      case result[:status]
      when :out_of_range_bet
        post(
          I18n.t(
            'modules.challenge.out_of_range_bet.',
            bet: result[:bet],
            current_stamina: result[:current_stamina],
            target: result[:target],
          ),
          data,
        )
      when :challenge_succeed, :challenge_failed
        I18n.t(
          'modules.challenge.inciting_words.',
          prob_percentage: '%d' % (result[:prob] * 100),
          stamina_succeed: result[:current_stamina] - result[:bet] + result[:target],
          stamina_failed: result[:current_stamina] - result[:bet],
        ).each do |message|
          post(message, data)
          sleep(2)
        end
        sleep(6)
        case result[:status]
        when :challenge_succeed
          post(I18n.t('modules.challenge.succeed.', result: result[:result]), data)
        when :challenge_failed
          post(I18n.t('modules.challenge.failed.', result: result[:result]), data)
        end
      end
    end
  end
end
