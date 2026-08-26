module HousePowerFormula
  INVERTER_SENSORS = %i[
    inverter_power
    inverter_power_1
    inverter_power_2
    inverter_power_3
    inverter_power_4
    inverter_power_5
  ].freeze
  private_constant :INVERTER_SENSORS

  OTHER_INCOMING_SENSORS = %i[
    grid_import_power
    battery_discharging_power
  ].freeze
  private_constant :OTHER_INCOMING_SENSORS

  INCOMING_SENSORS = INVERTER_SENSORS + OTHER_INCOMING_SENSORS
  private_constant :INCOMING_SENSORS

  OUTGOING_SENSORS = %i[
    battery_charging_power
    grid_export_power
    wallbox_power
    heatpump_power
  ].freeze
  private_constant :OUTGOING_SENSORS

  SENSORS = INCOMING_SENSORS + OUTGOING_SENSORS

  # One term of the sum: the sensor it comes from, whether the formula adds or
  # subtracts it, and the value it contributed.
  #
  # The statistics page prints the calculation from these terms, and the
  # calculator sums the same terms into the value it writes. One list feeds
  # both, so the page cannot show a formula that Ingest does not use.
  Term =
    Data.define(:key, :sign, :value) do
      def signed_value = sign * value

      def adds? = sign.positive?
    end

  class << self
    # Calculates the corrected house power based on known sensor powers
    def calculate(**powers)
      sum(terms(**powers))
    end

    # The terms of one calculation, in the order the formula adds them. It is
    # empty when the formula cannot run, and #sum then answers nothing.
    def terms(**powers)
      validate_keys!(powers)

      incoming = incoming_terms(powers)
      return [] if incoming.empty?

      outgoing = outgoing_terms(powers)
      return [] if outgoing.empty?

      incoming + outgoing
    end

    # The house power of a list of terms. A house cannot give power back, so a
    # negative sum becomes zero.
    def sum(terms)
      return if terms.empty?

      [terms.sum(&:signed_value), 0].max
    end

    # Which sensors take part, out of the ones the configuration offers, and
    # with which sign. The page prints the formula from this list while no
    # calculation has run yet, so the terms carry no value.
    def terms_for(keys)
      terms(**keys.to_h { [it, 0] })
    end

    private

    def incoming_terms(powers)
      inverter_terms(powers) + other_incoming_terms(powers)
    end

    def inverter_terms(powers)
      if powers[:inverter_power]
        # Single inverter
        [Term.new(key: :inverter_power, sign: 1, value: powers[:inverter_power])]
      else
        # multiple inverters
        INVERTER_SENSORS.drop(1).filter_map { term(it, 1, powers) }
      end
    end

    def other_incoming_terms(powers)
      OTHER_INCOMING_SENSORS.filter_map { term(it, 1, powers) }
    end

    def outgoing_terms(powers)
      OUTGOING_SENSORS.filter_map { term(it, -1, powers) }
    end

    def term(key, sign, powers)
      value = powers[key]
      Term.new(key:, sign:, value:) if value
    end

    def validate_keys!(powers)
      unknown_keys = powers.keys - SENSORS
      return if unknown_keys.empty?

      raise ArgumentError, "Unknown keys: #{unknown_keys.join(', ')}"
    end
  end
end
