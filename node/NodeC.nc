#include "utils.h"
#include "printf.h"
#include "utils.h"

#define NODE_ID TOS_NODE_ID
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

	uint8_t actual_status;
	message_t packet;
	my_msg_t* pckt;

	task void connectToPAN();

	event void Boot.booted(){
		call SplitControl.start();
	}

	event void SplitControl.startDone(error_t error){

		if(error == SUCCESS){
			printf("[NODE %u] Started. Connecting to PAN Coordinator\n",NODE_ID);
			post connectToPAN();
		}
	}

	event void SplitControl.stopDone(error_t error){}

	task void connectToPAN(){
		actual_status = CONNECT;
		pckt=call Packet.getPayload(&packet,sizeof(my_msg_t));
    	pckt->msg_type = CONNECT;
    	pckt->nodeID = NODE_ID;

    	if( call AMSend.send(AM_BROADCAST_ADDR,&packet,sizeof(my_msg_t)) == SUCCESS)
    	{
    		printf("[NODE %u] Sent Connect to PAN Coordinator\n", NODE_ID);
    	}
	}

	event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){

    	my_msg_t* rx_msg = (my_msg_t*)payload;
    	
    	if(rx_msg->msg_type == CONNACK)
    		printf("Connack received by PAN\n");
    	return msg;
	}

	event void AMSend.sendDone(message_t* buf,error_t err) {}

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
		printf("FIRED!\n");
	}
}
