#!/usr/bin/env raku

use v6.e.PREVIEW;

class DHT11 {
    use RPi::Wiring::Pi;

    constant DHTLIB_OK               =  0;
    constant DHTLIB_ERROR_CHECKSUM   =  -1;
    constant DHTLIB_ERROR_TIMEOUT    =  -2;
    constant DHTLIB_INVALID_VALUE    =  -999;
    constant DHTLIB_DHT11_WAKEUP     =  0.020;
    constant DHTLIB_DHT_WAKEUP       =  1;
    constant DHTLIB_TIMEOUT          =  120000;

    has uint8 @!bits = 0,0,0,0,0;

    has Int $.pin is required;

    has Numeric $.temperature;
    has Numeric $.humidity;

    method TWEAK() {
        if wiringPiSetup() == -1 {
            die "couldn't setup wiringpi";
        }
    }

    method read-sensor(Numeric $wakeup-delay ) {
        my int $mask = 0x80;
        my int $idx = 0;
        my int $i ;
        my $t;

        @!bits = 0,0,0,0,0;

        pinMode($!pin,OUTPUT);
        digitalWrite($!pin,HIGH);
        sleep(0.500);
        digitalWrite($!pin,LOW);
        sleep($wakeup-delay);
        digitalWrite($!pin,HIGH);
        pinMode($!pin,INPUT);

        $t = nano;

        loop {
            if digitalRead($!pin) == LOW {
                last;
            }
            if ( nano - $t ) > DHTLIB_TIMEOUT {
                note "timeout waiting for low";
                return DHTLIB_ERROR_TIMEOUT;
            }
        }

        $t = nano;
        while digitalRead($!pin) == LOW {
            if ( nano - $t ) > DHTLIB_TIMEOUT {
                note "timeout waiting for another low";
                return DHTLIB_ERROR_TIMEOUT;
            }
        }
        $t = nano;
        while digitalRead($!pin) == HIGH {
            if ( nano - $t ) > DHTLIB_TIMEOUT {
                note "timeout waiting for high";
                return DHTLIB_ERROR_TIMEOUT;
            }
        }

        for ^40 -> $i {
            $t = nano;
            while digitalRead($!pin) == LOW {
                if ( nano - $t ) > DHTLIB_TIMEOUT {
                    note "timeout waiting for low reading bits";
                    return DHTLIB_ERROR_TIMEOUT;
                }
            }
            $t = nano;
            while digitalRead($!pin) == HIGH {
                if ( nano - $t ) > DHTLIB_TIMEOUT {
                    note "timeout waiting for high reading bits";
                    return DHTLIB_ERROR_TIMEOUT;
                }
            }

            if ( nano - $t ) > 5000 {
                @!bits[$idx] +|= $mask;
            }

            $mask +>= 1;

            if $mask == 0 {
                $mask = 0x80;
                $idx++;
            }
        }

        pinMode($!pin,OUTPUT);
        digitalWrite($!pin,HIGH);
        return DHTLIB_OK;
    }

    method read-once( --> Int ) {
        given self.read-sensor(DHTLIB_DHT11_WAKEUP) {
            when DHTLIB_OK {
                $!humidity = @!bits[0];
                $!temperature = @!bits[2] + @!bits[3] * 0.1;
                my $sum = @!bits[^4].sum;
                if @!bits[4] != $sum {
                    DHTLIB_ERROR_CHECKSUM;
                }
                else {
                    $_;
                }
            }
            default {
                $!humidity = DHTLIB_INVALID_VALUE;
                $!temperature = DHTLIB_INVALID_VALUE;
                $_;
            }
        }

    }

    method read( --> Int ) {
        my $rv = DHTLIB_INVALID_VALUE;
        for ^15 {
            given self.read-once {
                when DHTLIB_OK {
                    $rv = $_;
                    last;
                }
                default {
                    $rv = $_;
                    sleep(0.1);
                }
            }
        }
        $rv;
    }

    class Reading {
        has Numeric $.temperature;
        has Numeric $.humidity;
    }

    method Supply( --> Supply ) {
        supply {
            whenever Supply.interval(1) -> $ {
                for ^15 {
                    if (self.read == DHTLIB_OK)  {
                        last;
                    }
                    sleep(0.001);
                }
                emit Reading.new(temperature => $.temperature, humidity => $.humidity);
            }
        }
    }

    sub MAIN() is export {
        my $dht = DHT11.new(pin => 0);

        react {
            whenever $dht -> $reading {
                say sprintf "Humidity is %.2f %%, \t Temperature is %.2f *C", $reading.humidity, $reading.temperature;
            }
        }
    }
}
# vim: ft=raku
