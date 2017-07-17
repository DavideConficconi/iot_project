#include "utils.h"
#include "printf.h"

#define NODE_ID TOS_NODE_ID
#define TIMER_DELAY 2000
#define CONNECT_RESEND_FACTOR 1000
#define TIME_OUT_TIMER (TIMER_DELAY + CONNECT_RESEND_FACTOR*NODE_ID)
#define QOS_TIME_OUT (TIME_OUT_TIMER / 10)

#define SENSOR_TIMER_MODULAR 20000
#define SENSOR_TIMER 2000 
#define DATA_TIMER (SENSOR_TIMER + SENSOR_TIMER_MODULAR*NODE_ID)


module NodeC
{
	uses {
		interface Boot;
		interface Packet;
		interface AMSend;
		interface SplitControl;
		interface Receive;
		interface PacketAcknowledgements;
		interface MessageTask;
		interface Read<uint16_t> as TemperatureSensor;
		interface Read<uint16_t> as HumiditySensor;
		interface Read<uint16_t> as LuminositySensor;

		interface Timer<TMilli> as RandomDataTimer;
		interface Timer<TMilli> as TimeOutTimer;
	}
}implementation{

	uint8_t actual_status = CONNECT;
	bool waiting_puback = FALSE; 
	uint16_t pan_address;
	uint8_t my_sensorID;
	message_t connect_packet;
	message_t subscribe_packet;
	message_t publish_packet;
	uint16_t sensor_data;

	task void connectToPANTask();
	task void connackRxTask();
	task void susbcribeTask();
	//void handle_publish(uint16_t dst, message_t packet);
	//void handle_subscribe(uint16_t dst, message_t packet);
	//void handle_connect(uint16_t dst, message_t packet);

	event void Boot.booted(){
		my_sensorID = TEMPERATURE_ID;//NODE_ID % TASKNUMBER;
		call SplitControl.start();
	}

	event void SplitControl.startDone(error_t error){
		//printf("MY ID %u\n", NODE_ID);
		if(error == SUCCESS){
			printf("[NODE %u] Started. Connecting to PAN Coordinator\n",NODE_ID);
			post connectToPANTask();
			//call MessageTask.postTask(AM_BROADCAST_ADDR,CONNECT,NODE_ID,NODE_ID,0,0);
		}
		else
        {
            call SplitControl.start();
        }
	}

	event void SplitControl.stopDone(error_t error){}

	task void connectToPANTask(){
		my_msg_t* pckt;
		pckt = call Packet.getPayload(&connect_packet,sizeof(my_msg_t));
		pckt->msg_type = CONNECT;
		pckt->qos = 0;
		pckt->nodeID = NODE_ID;
		pckt->topic = 0;
		pckt->payload = 0;
		//printf("[NODE %u] DEBUG: msg_type:%u, qos:%u nodeID: %u, topic: %u, payload:%u\n", NODE_ID, pckt->msg_type, pckt->qos,
		//	pckt->nodeID,pckt->topic,pckt->payload);
		if( call AMSend.send(AM_BROADCAST_ADDR ,&connect_packet,sizeof(my_msg_t)) == SUCCESS)
    	{
    		printf("[NODE %u] Sent Connect to PAN Coordinator\n", NODE_ID);
    	}
    	else
    		printf("[NODE %u] Fail to send Connect to PAN Coordinator\n", NODE_ID);

    	call TimeOutTimer.startOneShot(TIME_OUT_TIMER);
	}
	/*void handle_connect(uint16_t dst, message_t packet){

		//pckt=call Packet.getPayload(&packet,sizeof(my_msg_t));
    	//pckt->msg_type = CONNECT;
    	//pckt->nodeID = NODE_ID;

    	if( call AMSend.send(dst ,&packet,sizeof(my_msg_t)) == SUCCESS)
    	{
    		printf("[NODE %u] Sent Connect to PAN Coordinator\n", NODE_ID);
    	}
    	else
    		printf("[NODE %u] Fail to send Connect to PAN Coordinator\n", NODE_ID);

    	call TimeOutTimer.startOneShot(TIME_OUT_TIMER);
	}*/

	event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){

    	my_msg_t* rx_msg = (my_msg_t*)payload;
    	//printf("Sender address: %u\n", rx_msg->nodeID);
    	if(rx_msg->msg_type == CONNACK){
    		printf("[NODE %u] Connack received by PAN Coordinator address %u\n", NODE_ID, rx_msg->nodeID);
    		pan_address = rx_msg->nodeID;
    		actual_status = CONNACK;
    		call TimeOutTimer.stop();
    		post connackRxTask();
    	}else if ( rx_msg->msg_type == SUBACK){
    		actual_status = SUBACK;
    		call TimeOutTimer.stop();
    		printf("[NODE %u] Suback received by PAN Coordinator\n", NODE_ID);
    	}else if (rx_msg->msg_type == PUBACK){
    		waiting_puback = FALSE;
    		call TimeOutTimer.stop();
    		printf("[NODE %u] Puback received by PAN Coordinator\n", NODE_ID);
    	}else if (rx_msg->msg_type == PUBLISH){
    		printf("[NODE %u] Publish received by PAN Coordinator, Topic: %u, Data: %u\n", NODE_ID, rx_msg->topic,rx_msg->payload);
    	}

    	return msg;
	}



	event void MessageTask.runTask(uint16_t dst, uint8_t msg_type, uint8_t qos, uint16_t nodeID, uint8_t topic, uint16_t payload){
			my_msg_t* pckt;
			pckt = call Packet.getPayload(&publish_packet,sizeof(my_msg_t));
			pckt->msg_type = msg_type;
			pckt->qos = qos;
			pckt->nodeID = nodeID;
			pckt->topic = topic;
			pckt->payload = payload;
			//printf("[NODE %u] DEBUG: msg_type:%u, nodeID: %u, topic: %u, payload:%u\n", NODE_ID, msg_type,nodeID,topic,payload);
			waiting_puback = TRUE;
	    	if( call AMSend.send(dst ,&publish_packet,sizeof(my_msg_t)) == SUCCESS)
	    	{
	    		printf("[NODE %u] Sent Publish to PAN Coordinator, Topic:%u , Data: %u\n", NODE_ID, my_sensorID, sensor_data);
	    	}
	    	else
	    		printf("[NODE %u] FAIL!! Publish. Topic:%u , Data: %u\n", NODE_ID, my_sensorID, sensor_data);
	    	call TimeOutTimer.startOneShot(TIME_OUT_TIMER);
	}
	
	task void connackRxTask(){
		call RandomDataTimer.startPeriodic(DATA_TIMER);
        actual_status = SUBSCRIBE;
        post susbcribeTask();
	}

	task void susbcribeTask(){
		my_msg_t* pckt;
		pckt = call Packet.getPayload(&subscribe_packet,sizeof(my_msg_t));
		pckt->msg_type = SUBSCRIBE;
		pckt->qos = 0;
		pckt->nodeID = NODE_ID;
		pckt->topic = my_sensorID;// + 1;
		pckt->payload = 0;
		//printf("[NODE %u] DEBUG: msg_type:%u, qos:%u nodeID: %u, topic: %u, payload:%u\n", NODE_ID, pckt->msg_type, pckt->qos,
		//	pckt->nodeID,pckt->topic,pckt->payload);
		if( call AMSend.send(pan_address ,&subscribe_packet,sizeof(my_msg_t)) == SUCCESS)
    	{
    		printf("[NODE %u] Sent Subscribe to PAN Coordinator\n", NODE_ID);
    	}
    	else
    		printf("[NODE %u] Fail to send Subscribe to PAN Coordinator\n", NODE_ID);

    	call TimeOutTimer.startOneShot(TIME_OUT_TIMER);
	}

/*	void handle_subscribe(uint16_t dst, message_t packet){

    	if( call AMSend.send(dst ,&packet,sizeof(my_msg_t)) == SUCCESS)
    	{
    		printf("[NODE %u] Sent Subscribe to PAN Coordinator\n", NODE_ID);
    	}
    	call TimeOutTimer.startOneShot(TIME_OUT_TIMER);
	}*/

	event void AMSend.sendDone(message_t* buf,error_t err) {
		if((&connect_packet == buf || &subscribe_packet == buf) && err == SUCCESS );
			//printf("[NODE %u] Packet Sent\n", NODE_ID);
		else if ( err != SUCCESS)
			printf("[NODE %u] Packet NOT sent, failed\n", NODE_ID);
	
		if ( call PacketAcknowledgements.wasAcked( buf ) );
		 // printf("[NODE %u] Packet acked!\n", NODE_ID);
	}

/*
	void handle_publish(uint16_t dst, message_t packet){
		waiting_puback = TRUE;
    	if( call AMSend.send(dst ,&packet,sizeof(my_msg_t)) == SUCCESS)
    	{
    		printf("[NODE %u] Sent Publish to PAN Coordinator, Topic:%u , Data: %u\n", NODE_ID, my_sensorID, sensor_data);
    	}
    	else
    		printf("[NODE %u] FAIL!! Publish. Topic:%u , Data: %u\n", NODE_ID, my_sensorID, sensor_data);
    	call TimeOutTimer.startOneShot(TIME_OUT_TIMER);
	}*/
	// si può fare un codice solo?
	event void TemperatureSensor.readDone(error_t result, uint16_t data) {
		printf("[NODE %u]New data available from Topic:%u; Temperature: %u \n",NODE_ID, my_sensorID, data);
		sensor_data = data;
		call MessageTask.postTask(pan_address,PUBLISH,0,NODE_ID,my_sensorID,data);

	}
	event void HumiditySensor.readDone(error_t result, uint16_t data) {
		printf("[NODE %u]New data available from Topic:%u; Humidity: %u\n",NODE_ID, my_sensorID, data);
		sensor_data = data;
		call MessageTask.postTask(pan_address, PUBLISH,0,NODE_ID,my_sensorID,data);
	}
	event void LuminositySensor.readDone(error_t result, uint16_t data) {
		printf("[NODE %u]New data available from Topic:%u; Luminosity: %u\n",NODE_ID,my_sensorID, data);
		sensor_data = data;
		call MessageTask.postTask(pan_address, PUBLISH,0,NODE_ID,my_sensorID,data);
	}
	event void RandomDataTimer.fired() {
        switch(my_sensorID)
        {
        case TEMPERATURE_ID:
            call TemperatureSensor.read();
            break;
        case HUMIDITY_ID:
            call HumiditySensor.read();
            break;
        case LUMINOSITY_ID:
            call LuminositySensor.read();
            break;
        }
	}
	event void TimeOutTimer.fired() {
		if(actual_status == CONNECT){
			printf("[NODE %u] Connack not received. Try again\n",NODE_ID);
			post connectToPANTask();
		}else if (actual_status == SUBSCRIBE){
			printf("[NODE %u] Suback not received. Try again\n",NODE_ID);
			post susbcribeTask();
		}else if (waiting_puback){
			//da controllare la storia delle publish con timer...
			printf("[NODE %u] Puback not received. Try again\n",NODE_ID);
			call MessageTask.postTask(pan_address,PUBLISH,0,NODE_ID,my_sensorID,sensor_data);
		}else
			printf("[NODE %u] Timeout expired, but nothing to resend.\n", NODE_ID);
	}
}
