#include "utils.h"
#include "printf.h"
#include "utils.h"

#define NODE_ID TOS_NODE_ID
#define TIMER_DELAY 10000
module NodeC
{
	uses {
		interface Boot;
		interface Packet;
		interface AMSend;
		interface SplitControl;
		interface Receive;
		interface PacketAcknowledgements;

		interface Read<uint16_t> as TemperatureSensor;
		interface Read<uint16_t> as HumiditySensor;
		interface Read<uint16_t> as LuminositySensor;

		interface Timer<TMilli> as RandomDataTimer;
		interface Timer<TMilli> as TimeOutTimer;
	}
}implementation{

	uint8_t actual_status = CONNECT;
	uint8_t my_sensorID;
	message_t packet;
	my_msg_t* pckt;

	task void connectToPAN();
	void handle_connect();

	event void Boot.booted(){
		call SplitControl.start();
	}

	event void SplitControl.startDone(error_t error){

		if(error == SUCCESS){
			printf("[NODE %u] Started. Connecting to PAN Coordinator\n",NODE_ID);
			post connectToPAN();
		}
		else
        {
            call SplitControl.start();
        }
	}

	event void SplitControl.stopDone(error_t error){}

	task void connectToPAN(){
		handle_connect();
	}
	void handle_connect(){
		pckt=call Packet.getPayload(&packet,sizeof(my_msg_t));
    	pckt->msg_type = CONNECT;
    	pckt->nodeID = NODE_ID;

    	if( call AMSend.send(AM_PAN_COORD_ADDR,&packet,sizeof(my_msg_t)) == SUCCESS)
    	{
    		printf("[NODE %u] Sent Connect to PAN Coordinator\n", NODE_ID);
    	}
    	call TimeOutTimer.startOneShot(TIMER_DELAY);
	}

	event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){

    	my_msg_t* rx_msg = (my_msg_t*)payload;
    	
    	if(rx_msg->msg_type == CONNACK){
    		printf("Connack received by PAN Coordinator\n");
    		actual_status = CONNACK;
    	}

    	return msg;
	}

	event void AMSend.sendDone(message_t* buf,error_t err) {
		if(&packet == buf && err == SUCCESS )
			printf("[NODE %u] Packet Sent\n", NODE_ID);
		else if ( err != SUCCESS)
			printf("[NODE %u] Packet NOT sent, failed\n", NODE_ID);
	
		if ( call PacketAcknowledgements.wasAcked( buf ) )
		  printf("[NODE %u] Packet acked!\n", NODE_ID);
	}

	event void TemperatureSensor.readDone(error_t result, uint16_t data) {
		printf("Temp\n");
	}
	event void HumiditySensor.readDone(error_t result, uint16_t data) {
		printf("Hum\n");
	}
	event void LuminositySensor.readDone(error_t result, uint16_t data) {
		printf("Lum\n");
	}
	event void RandomDataTimer.fired() {
		printf("FIRED!\n");
	}
	event void TimeOutTimer.fired() {
		if(actual_status == CONNECT){
			printf("[NODE %u] Connack not received. Try again\n",NODE_ID);
			post connectToPAN();
		}else
			printf("[NODE %u] Timeout for Connack expired, but already received.\n", NODE_ID);
	}
}
