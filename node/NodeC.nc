/*
*	This is the Node component. It is composed by a Communication part and random data generation part.
*	The communication part is composed by a Sendr one and Receiver one. Based on the status of the node and on the message received
*	the component will react consequently. Primarly the node tries to connect to a Coordinator by sending a Broadcast message. Once
*	the address is acquired it will record it and then subscribe to two topic. The node then generate data on the three different topic
*	in a round-robin fashion.
*	The connect and subscribe message are sent and if a Ack message is not received the node will try again after a 2s + 1s*Node ID interval
*	The QoS levels are set at compile time in a random way.
*	The node will subscribe to 2 topic randomly chosen among the three available. 
*	The data are generated at a regular interval of 20s + 2s*Node ID.
*/
#include "utils.h"
#include "printf.h"

#define NODE_ID TOS_NODE_ID
#define TIMER_DELAY 2000
#define CONNECT_RESEND_FACTOR 1000
#define TIME_OUT_TIMER (TIMER_DELAY + CONNECT_RESEND_FACTOR*NODE_ID)

#define QOS_LVL_TMP (NODE_ID % QOS_LEVELS)
#define QOS_LVL_HUM ((NODE_ID - 1) % QOS_LEVELS)
#define QOS_LVL_LUM ((NODE_ID + 1) % QOS_LEVELS)

#define PRIMARY_TOPIC (NODE_ID % TASKNUMBER)
#define SECONDARY_TOPIC ((NODE_ID - 1) % TASKNUMBER)


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
	message_t puback_packet;
	uint16_t sensor_data;
	bool subscribed_topic[2];

	task void connectToPANTask();
	task void connackRxTask();
	task void susbcribePrimaryTask();
	task void pubAckTask();
	task void susbcribeSecondaryTask();
	uint8_t determineQoS(uint8_t topic);


	event void Boot.booted(){
		my_sensorID = NODE_ID % TASKNUMBER;
		call SplitControl.start();
		/*printf("Primary topic: %u, P_QoS:%u, Secondary topic: %u, S_Qos: %u, My sensor:%u\n", 
			PRIMARY_TOPIC, determineQoS(PRIMARY_TOPIC), SECONDARY_TOPIC, determineQoS(SECONDARY_TOPIC), my_sensorID);
	*/}

/*************Initiation of the node by start to connect to PAN Coordinator*************/
	event void SplitControl.startDone(error_t error){
		//printf("MY ID %u\n", NODE_ID);
		if(error == SUCCESS){
			printf("[NODE %u] Started. Connecting to PAN Coordinator\n",NODE_ID);
			post connectToPANTask();
		}
		else
        {
            call SplitControl.start();
        }
	}

	event void SplitControl.stopDone(error_t error){}
/*************Function to determine the QoS associated to a given Topic*************/
	uint8_t determineQoS(uint8_t topic){
		switch(topic){
        case TEMPERATURE_ID:
            return QOS_LVL_TMP;
        case HUMIDITY_ID:
            return QOS_LVL_HUM;
        case LUMINOSITY_ID:
        	return QOS_LVL_LUM;
        default:
        	return 0;
		}
	}
/*************Start the connection with the PAN Coordinator*************/
/* It starts by sending in Broadcast a message to require the Connection
* call a Timer that will resend the Connect message if no one answer
*/
	task void connectToPANTask(){
		my_msg_t* pckt;
		pckt = call Packet.getPayload(&connect_packet,sizeof(my_msg_t));
		pckt->msg_type = CONNECT;
		pckt->nodeID = NODE_ID;
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
/*************Handle the answer when receive a Connack*************/
/* Change the status of the node and then try to Subscribe for the Primary Topic	
*/
	task void connackRxTask(){
        actual_status = SUBSCRIBE;
        post susbcribePrimaryTask();
	}
/*************Subscribe to the Primary Topic*************/
/* Create the packet and send it to the PAN Coordinator that after a Connack message it is at
* known address.
* If a QoS is set then the Node will wait for a Suback from the PAN Coordinator
*/
	task void susbcribePrimaryTask(){
			uint8_t qos;
			my_msg_t* pckt;
			qos = determineQoS(PRIMARY_TOPIC);
			pckt = call Packet.getPayload(&subscribe_packet,sizeof(my_msg_t));
			pckt->msg_type = SUBSCRIBE;
			pckt->qos = qos;
			pckt->nodeID = NODE_ID;
			pckt->topic = PRIMARY_TOPIC;
			//printf("[NODE %u] DEBUG: msg_type:%u, qos:%u nodeID: %u, topic: %u, payload:%u\n", NODE_ID, pckt->msg_type, pckt->qos,
			//	pckt->nodeID,pckt->topic,pckt->payload);
			if( call AMSend.send(pan_address ,&subscribe_packet,sizeof(my_msg_t)) == SUCCESS)
	    	{
	    		printf("[NODE %u] Sent Subscribe to PAN Coordinator to Topic: %u, QoS: %u\n", NODE_ID, pckt->topic, pckt->qos);
	    	}
	    	else
	    		printf("[NODE %u] Fail to send Subscribe to PAN Coordinator to Topic: %u, QoS: %u\n", NODE_ID, pckt->topic, pckt->qos);
	    	if(qos)
	    		call TimeOutTimer.startOneShot(TIME_OUT_TIMER);
	}


/*************Subscribe to the secondary Topic*************/
/* Same as above, in addition the random data generation process is started
*/
	task void susbcribeSecondaryTask(){
		uint8_t qos;
		my_msg_t* pckt;
		qos = determineQoS(SECONDARY_TOPIC);
		pckt = call Packet.getPayload(&subscribe_packet,sizeof(my_msg_t));
		pckt->msg_type = SUBSCRIBE;
		pckt->qos = qos;
		pckt->nodeID = NODE_ID;
		pckt->topic = SECONDARY_TOPIC;
		//printf("[NODE %u] DEBUG: msg_type:%u, qos:%u nodeID: %u, topic: %u, payload:%u\n", NODE_ID, pckt->msg_type, pckt->qos,
		//	pckt->nodeID,pckt->topic,pckt->payload);
		if( call AMSend.send(pan_address ,&subscribe_packet,sizeof(my_msg_t)) == SUCCESS)
    	{
    		printf("[NODE %u] Sent Subscribe to PAN Coordinator to Topic: %u, QoS: %u\n", NODE_ID, pckt->topic, pckt->qos);
    	}
    	else
    		printf("[NODE %u] Fail to send Subscribe to PAN Coordinator to Topic: %u, QoS: %u\n", NODE_ID, pckt->topic, pckt->qos);
    	if(qos)
    		call TimeOutTimer.startOneShot(TIME_OUT_TIMER);
    	call RandomDataTimer.startPeriodic(DATA_TIMER);
	}

/*************Answer with a PubAck message to the PAN if required*************/
/*Create a PubAck message and send it to the PAN whenever it is required
*/
	task void pubAckTask(){
			my_msg_t* pckt;
			pckt = call Packet.getPayload(&puback_packet,sizeof(my_msg_t));
			pckt->msg_type = PUBACK;
			pckt->nodeID = NODE_ID;
			//printf("[NODE %u] DEBUG: msg_type:%u, qos:%u nodeID: %u, topic: %u, payload:%u\n", NODE_ID, pckt->msg_type, pckt->qos,
			//	pckt->nodeID,pckt->topic,pckt->payload);
			if( call AMSend.send(pan_address ,&puback_packet,sizeof(my_msg_t)) == SUCCESS)
	    	{
	    		printf("[NODE %u] Sent PUBACK to PAN Coordinator\n", NODE_ID);
	    	}
	    	else
	    		printf("[NODE %u] Fail to send PUBACK to PAN Coordinator\n", NODE_ID);

	}


/*************Publish in an Asynchronous way*************/
/* Create the Packet and put the Node in a status that will wait for a Puback and resend it after a timer
*/
	event void MessageTask.runTask(uint16_t dst, uint8_t msg_type, uint8_t qos, uint16_t nodeID, uint8_t topic, uint16_t payload){
		my_msg_t* pckt;
		pckt = call Packet.getPayload(&publish_packet,sizeof(my_msg_t));
		pckt->msg_type = msg_type;
		pckt->qos = qos;
		pckt->nodeID = nodeID;
		pckt->topic = topic;
		pckt->payload = payload;
		//printf("[NODE %u] DEBUG: msg_type:%u, nodeID: %u, topic: %u, payload:%u\n", NODE_ID, msg_type,nodeID,topic,payload);
    	if( call AMSend.send(dst ,&publish_packet,sizeof(my_msg_t)) == SUCCESS)
    	{
    		printf("[NODE %u] Sent Publish to PAN Coordinator, QoS:%u, Topic:%u , Data: %u\n", NODE_ID, qos, my_sensorID, sensor_data);
    	}
    	else
    		printf("[NODE %u] FAIL!! Publish. QoS:%u, Topic:%u , Data: %u\n", NODE_ID, qos, my_sensorID, sensor_data);
    	if(qos){
    		waiting_puback = TRUE;
    		call TimeOutTimer.startOneShot(TIME_OUT_TIMER);
    	}
	}

/*************Finalization of sender*************/
	event void AMSend.sendDone(message_t* buf,error_t err) {
		if((&connect_packet == buf || &subscribe_packet == buf) && err == SUCCESS );
			//printf("[NODE %u] Packet Sent\n", NODE_ID);
		else if ( err != SUCCESS)
			printf("[NODE %u] Packet NOT sent, failed\n", NODE_ID);
	
		if ( call PacketAcknowledgements.wasAcked( buf ) );
		 // printf("[NODE %u] Packet acked!\n", NODE_ID);
	}

/*************Receive Interface*************/
/* Connack: save the address of the PAN Coordinator, stop the waiting and react correspondingly
*  Suback: react depending on which suback is received for the primary or secondary topic
*  Puback: Ok, stop resending if QoS set to one.
*  Publish: if required based on the QoS level set by the previous subscribe, send the Puback
*/
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
    		if(rx_msg->topic == PRIMARY_TOPIC && !subscribed_topic[0]){
    			subscribed_topic[0] = TRUE;
    			actual_status = SUBSCRIBE;
    			call TimeOutTimer.stop();
    			post susbcribeSecondaryTask();
    		}else if( rx_msg->topic == SECONDARY_TOPIC && !subscribed_topic[1]){
    			actual_status = SUBACK;
    			subscribed_topic[1] = TRUE;
    			call TimeOutTimer.stop();
    		}
    		printf("[NODE %u] Suback received by PAN Coordinator for Topic %u\n", NODE_ID, rx_msg->topic);
    	}else if (rx_msg->msg_type == PUBACK){
    		waiting_puback = FALSE;
    		call TimeOutTimer.stop();
    		printf("[NODE %u] Puback received by PAN Coordinator\n", NODE_ID);
    	}else if (rx_msg->msg_type == PUBLISH){
    		printf("[NODE %u] Publish received by PAN Coordinator, Topic: %u, Data: %u\n", NODE_ID, rx_msg->topic,rx_msg->payload);
    		if(determineQoS(rx_msg->topic))
    			post pubAckTask();
    	}

    	return msg;
	}

/*************Random Read from the different sensors*************/
	event void TemperatureSensor.readDone(error_t result, uint16_t data) {
		printf("[NODE %u]New data available from Topic:%u; Temperature: %u\n",NODE_ID, my_sensorID, data);
		sensor_data = data;
		call MessageTask.postTask(pan_address,PUBLISH,QOS_LVL_TMP,NODE_ID,my_sensorID,data);

	}
	event void HumiditySensor.readDone(error_t result, uint16_t data) {
		printf("[NODE %u]New data available from Topic:%u; Humidity: %u\n",NODE_ID, my_sensorID, data);
		sensor_data = data;
		call MessageTask.postTask(pan_address, PUBLISH,QOS_LVL_HUM,NODE_ID,my_sensorID,data);
	}
	event void LuminositySensor.readDone(error_t result, uint16_t data) {
		printf("[NODE %u]New data available from Topic:%u; Luminosity: %u\n",NODE_ID,my_sensorID, data);
		sensor_data = data;
		call MessageTask.postTask(pan_address, PUBLISH,QOS_LVL_LUM,NODE_ID,my_sensorID,data);
	}

/*************Periodic Timer for different reads*************/
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
        my_sensorID = (my_sensorID + 1) % TASKNUMBER;
	}

/*************Time Out Timer for resending messages*************/
	event void TimeOutTimer.fired() {
		if(actual_status == CONNECT){
			printf("[NODE %u] Connack not received. Try again\n",NODE_ID);
			post connectToPANTask();
		}else if (actual_status == SUBSCRIBE){
			printf("[NODE %u] Suback not received. Try again\n",NODE_ID);
    		if(!subscribed_topic[0]){
    			post susbcribePrimaryTask();
    		}else if(!subscribed_topic[1]){
    			post susbcribeSecondaryTask();
    		}
		}else if (waiting_puback){

			printf("[NODE %u] Puback not received. Try again\n",NODE_ID);
			call MessageTask.postTask(pan_address,PUBLISH,0,NODE_ID,my_sensorID,sensor_data);
		}else
			printf("[NODE %u] Timeout expired, but nothing to resend.\n", NODE_ID);
	}
}
