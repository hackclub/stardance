from machine import Pin
from time import ticks_ms, ticks_diff, sleep_ms

sensor = Pin(2, Pin.IN, Pin.PULL_UP)
events = []
previous = sensor.value()
last_event = None
last_report = ticks_ms()

while True:
    now = ticks_ms()
    current = sensor.value()
    if current == 0 and previous == 1:
        if last_event is None or ticks_diff(now, last_event) >= 60:
            events.append(now)
            last_event = now
    previous = current
    while events and ticks_diff(now, events[0]) >= 2000:
        events.pop(0)
    if ticks_diff(now, last_report) >= 100:
        print('Suspicion: {}%'.format(min(100, len(events) * 10)))
        last_report = now
    sleep_ms(1)
