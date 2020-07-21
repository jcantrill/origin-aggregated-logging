#--
# Copyright (C)2007 Tony Arcieri
# You can redistribute this under the terms of the Ruby license
# See file LICENSE for details
#++

module Coolio
  class TimerWatcher
    # The actual implementation of this class resides in the C extension
    # Here we metaprogram proper event_callbacks for the callback methods
    # These can take a block and store it to be called when the event
    # is actually fired.

    extend Meta
    event_callback :on_timer
  end
end
