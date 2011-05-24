// -*- tab-width: 4; Mode: C++; c-basic-offset: 4; indent-tabs-mode: nil -*-

//Function that will read the radio data, limit servos and trigger a failsafe
// ----------------------------------------------------------------------------
byte failsafeCounter = 0;		// we wait a second to take over the throttle and send the plane circling


void init_rc_in()
{
	// set rc channel ranges
	g.rc_1.set_angle(4500);
	g.rc_2.set_angle(4500);
	g.rc_3.set_range(0,1000);
	g.rc_3.scale_output = .9;
	g.rc_4.set_angle(4500);

	g.rc_1.set_type(RC_CHANNEL_ANGLE_RAW);
	g.rc_2.set_type(RC_CHANNEL_ANGLE_RAW);
	g.rc_4.set_type(RC_CHANNEL_ANGLE_RAW);

	// set rc dead zones
	g.rc_1.dead_zone = 60;		// 60 = .6 degrees
	g.rc_2.dead_zone = 60;
	g.rc_3.dead_zone = 60;
	g.rc_4.dead_zone = 500;

	//set auxiliary ranges
	g.rc_5.set_range(0,1000);
	g.rc_5.set_filter(false);
	g.rc_6.set_range(0,1000);
	g.rc_7.set_range(0,1000);
	g.rc_8.set_range(0,1000);

	#if CHANNEL_6_TUNING == CH6_STABLIZE_KD
		g.rc_6.set_range(0,300);

	#elif CHANNEL_6_TUNING == CH6_BARO_KP
		g.rc_6.set_range(0,800);

	#elif CHANNEL_6_TUNING == CH6_BARO_KD
		g.rc_6.set_range(0,500);

	#elif CHANNEL_6_TUNING == CH6_Y6_SCALING
		g.rc_6.set_range(800,1000);
	#endif

	//catch bad RC_3 min values
}

void init_rc_out()
{
	#if ARM_AT_STARTUP == 1
		motor_armed = 1;
	#endif


	APM_RC.Init();		// APM Radio initialization

    // fix for crazy output
    OCR1B = 0xFFFF;     // PB6, OUT3
    OCR1C = 0xFFFF;     // PB7, OUT4
    OCR5B = 0xFFFF;     // PL4, OUT1
    OCR5C = 0xFFFF;     // PL5, OUT2
    OCR4B = 0xFFFF;     // PH4, OUT6
    OCR4C = 0xFFFF;     // PH5, OUT5

	// don't fuss if we are calibrating
	if(g.esc_calibrate == 1)
		return;

    if(g.rc_3.radio_min <= 1200){
        output_min();
    }

	for(byte i = 0; i < 5; i++){
		delay(20);
		read_radio();
	}

    // sanity check
    if(g.rc_3.radio_min >= 1300){
        g.rc_3.radio_min = g.rc_3.radio_in;
        output_min();
    }
}

void output_min()
{
	APM_RC.OutputCh(CH_1, 	g.rc_3.radio_min);					// Initialization of servo outputs
	APM_RC.OutputCh(CH_2, 	g.rc_3.radio_min);
	APM_RC.OutputCh(CH_3, 	g.rc_3.radio_min);
	APM_RC.OutputCh(CH_4, 	g.rc_3.radio_min);

	APM_RC.OutputCh(CH_7,   g.rc_3.radio_min);
    APM_RC.OutputCh(CH_8,   g.rc_3.radio_min);

	#if FRAME_CONFIG ==	OCTA_FRAME
	APM_RC.OutputCh(CH_10,   g.rc_3.radio_min);
    APM_RC.OutputCh(CH_11,   g.rc_3.radio_min);
	#endif

}
void read_radio()
{
	g.rc_1.set_pwm(APM_RC.InputCh(CH_1));
	g.rc_2.set_pwm(APM_RC.InputCh(CH_2));
	g.rc_3.set_pwm(APM_RC.InputCh(CH_3));
	g.rc_4.set_pwm(APM_RC.InputCh(CH_4));
	g.rc_5.set_pwm(APM_RC.InputCh(CH_5));
	g.rc_6.set_pwm(APM_RC.InputCh(CH_6));
	g.rc_7.set_pwm(APM_RC.InputCh(CH_7));
	g.rc_8.set_pwm(APM_RC.InputCh(CH_8));


	// limit our input to 800 so we can still pitch and roll
	g.rc_3.control_in = min(g.rc_3.control_in, 800);

	//throttle_failsafe(g.rc_3.radio_in);

	/*
	Serial.printf_P(PSTR("OUT 1: %d\t2: %d\t3: %d\t4: %d \n"),
				g.rc_1.control_in,
				g.rc_2.control_in,
				g.rc_3.control_in,
				g.rc_4.control_in);
	*/
}

void throttle_failsafe(uint16_t pwm)
{
	if(g.throttle_fs_enabled == 0)
		return;

	//check for failsafe and debounce funky reads
	// ------------------------------------------
	if (pwm < g.throttle_fs_value){
		// we detect a failsafe from radio
		// throttle has dropped below the mark
		failsafeCounter++;
		if (failsafeCounter == 9){
			SendDebug("MSG FS ON ");
			SendDebugln(pwm, DEC);
		}else if(failsafeCounter == 10) {
			ch3_failsafe = true;
			//set_failsafe(true);
			//failsafeCounter = 10;
		}else if (failsafeCounter > 10){
			failsafeCounter = 11;
		}

	}else if(failsafeCounter > 0){
		// we are no longer in failsafe condition
		// but we need to recover quickly
		failsafeCounter--;
		if (failsafeCounter > 3){
			failsafeCounter = 3;
		}
		if (failsafeCounter == 1){
			SendDebug("MSG FS OFF ");
			SendDebugln(pwm, DEC);
		}else if(failsafeCounter == 0) {
			ch3_failsafe = false;
			//set_failsafe(false);
			//failsafeCounter = -1;
		}else if (failsafeCounter <0){
			failsafeCounter = -1;
		}
	}
}

void trim_radio()
{
	for (byte i = 0; i < 30; i++){
		read_radio();
	}

	g.rc_1.trim();	// roll
	g.rc_2.trim();	// pitch
	g.rc_4.trim();	// yaw

	g.rc_1.save_eeprom();
	g.rc_2.save_eeprom();
	g.rc_4.save_eeprom();
}

void trim_yaw()
{
	for (byte i = 0; i < 30; i++){
		read_radio();
	}
	g.rc_4.trim();	// yaw
}

