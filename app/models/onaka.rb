# frozen_string_literal: true

require './app/lib/slack_client'
require './app/lib/i18n_settings'
require './app/lib/connect_database'

# おなか占いの出目クラス。
# Emoji と本クラスは多対一の関係を持つ。
class Onaka < ActiveRecord::Base
  has_many :users, through: :user_onakas
  has_many :user_onakas
  has_many :emojis

  scope :order_by_frequency, -> { order(frequency: :desc) }
  scope :has_appeared, -> { where.not(frequency: 0..1) } # 2回以上の出現をもって appeared とする

  def display_name
    custom_display_name || ":onaka: :#{name}:"
  end

  def rank
    Onaka.where.not(frequency: 0..frequency).count + 1
  end

  RARITY = %w[
    :rarity_n:
    :rarity_r:
    :rarity_sr:
    :rarity_ssr:
    :rarity_hr:
    :rarity_ur:
    :rarity_x:
    :rarity_question:
  ].freeze

  def rarity_level
    (rank - 1) * RARITY.size / Onaka.has_appeared.count
  end

  # Slack の emoji shortcode にマッチする正規表現
  EMOJI_PATTERN = %r[(?<=:)[^:;.,!?@#$%^&*(){}\[\]<>\/\\=\s]+(?=:)].freeze

  def self.update_freqs(text)
    text.scan(EMOJI_PATTERN).group_by(&:itself).transform_values(&:size).each do |emoji, freq|
      Emoji.find_by(name: emoji)&.onaka&.then { |onaka| onaka.update!(frequency: onaka.frequency + freq) }
    end
  end

  # Zipf 分布 f(k; s = 0.5, N) の分母
  ZIPF = Hash.new { |h, n| h[n] = (n.zero? ? 0.0 : h[n - 1] + 1.fdiv(n**0.5)) }

  # XXX: 突然 ZIPF[Onaka.count] すると Stack level too deep が出るため
  Onaka.has_appeared.count.times(&ZIPF.method(:[]))

  def self.draw(count = 1)
    onaka_size = Onaka.has_appeared.count

    Array.new(count) do
      rval = rand(0...ZIPF[onaka_size])

      index = (0...onaka_size).bsearch { |e|
        (ZIPF[e]...ZIPF[e + 1]).cover?(rval) ? 0 : rval <=> ZIPF[e]
      }

      Onaka.has_appeared.order_by_frequency.offset(index).first
    end
  end

  def self.update_frequency(text)
    ActiveRecord::Base.transaction(isolation: :serializable) do
      Emoji.where(name: text.scan(EMOJI_PATTERN).uniq).find_each do |emoji|
        emoji.onaka.then do |onaka|
          onaka.update!(frequency: onaka.frequency + 1)
        end
      end
    end
  end
end
