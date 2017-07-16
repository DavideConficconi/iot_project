#include "utils.h"
#include "printf.h"

#define NNODE 8
#define PAN_ID TOS_NODE_ID

module PANCoordinatorC {
	uses {
		interface Boot;
		interface AMSend;
        interface SplitControl;
        interface Receive;
        interface PacketAcknowledgements;
        interface Packet;
        interface MessageTask;
	}
}	implementation {
    bool connected_nodes[NNODE];
    bool sub_nodes_tmp[NNODE];
    bool sub_nodes_hum[NNODE];
    bool sub_nodes_lum[NNODE];

	message_t global_packet;
    //my_msg_t * pckt;
    //uint16_t node_ids;
    //uint16_t payload_rx;
    //uint8_t topic_rx;
    message_t connack_packet;
    message_t suback_packet;
    message_t publish_packet;
    message_t puback_packet;
    message_t packet;

	void handle_publish(uint16_t node_address, uint8_t topic, uint8_t qos, uint16_t payload);
    void handle_suback(uint16_t dst, uint8_t qos);
    void handle_connack(uint16_t dst, uint8_t qos);
    void handle_puback(uint16_t dst, uint8_t qos);

	//task void sendConnackTask();
    //task void sendSubAckTask();
    //task void forwardPublishTask();
    //void handle_publish(uint8_t node_address,uint8_t topic, uint16_t data);

	event void Boot.booted()
    {
        call SplitControl.start();
    }

    event void SplitControl.startDone(error_t err)
    {
        if(err == SUCCESS)
        {
            printf("[PAN Coordinator] Started! at address: %u\n", PAN_ID);
        }
        else
        {
            call SplitControl.start();
        }
    }

    event void SplitControl.stopDone(error_t err) {
        printf("[PAN Coordinator] Something bad happened...\n");
    }

    event message_t* Receive.receive(message_t* buf, void* payload, uint8_t len){

    	my_msg_t* rx_msg = (my_msg_t*)payload;
    	//printf("LENGTH: %u\n", len);
    	if(rx_msg->msg_type == CONNECT){
            //printf("Node %u sent me a packet, Previous message %u\n",rx_msg->nodeID, node_ids);
            //node_ids = rx_msg->nodeID;
            //printf("NODE %u\n",rx_msg->nodeID);
            if(!connected_nodes[rx_msg->nodeID - 1]){
                connected_nodes[rx_msg->nodeID - 1] = TRUE;
                //post sendConnackTask();
                printf("[PAN Coordinator] CONNECT received from node :%u, MY ID: %u\n",rx_msg->nodeID, PAN_ID);
                call MessageTask.postTask(rx_msg->nodeID, CONNACK, rx_msg->qos, PAN_ID, 0, 0);
            }
            else
                printf("[PAN Coordinator] Received CONNECT message from %u but already connected\n",rx_msg->nodeID);
        }else if (rx_msg->msg_type == SUBSCRIBE){
            //node_ids = rx_msg->nodeID;
            //topic_rx = rx_msg->topic;
            switch(rx_msg->topic)
            {
            case TEMPERATURE_ID:
                sub_nodes_tmp[rx_msg->nodeID - 1] = TRUE;
                break;
            case HUMIDITY_ID:
                sub_nodes_hum[rx_msg->nodeID - 1] = TRUE;
                break;
            case LUMINOSITY_ID:
                sub_nodes_lum[rx_msg->nodeID - 1] = TRUE;
                break;
            default:
                printf("[PAN Coordinator] Bad topic received for subscribe\n");
                break;
            }
            //topic_rx = rx_msg->topic;
            printf("[PAN Coordinator] SUBSCRIBE received from Node %u to topic %u\n",rx_msg->nodeID, rx_msg->topic);
            call MessageTask.postTask(rx_msg->nodeID, SUBACK, 0, PAN_ID, 0, 0);

        }else if (rx_msg->msg_type == PUBLISH){
            //topic_rx = rx_msg->topic;
            //payload_rx = rx_msg->payload;
            //node_ids = rx_msg->nodeID;
            //post forwardPublishTask();
            call MessageTask.postTask(rx_msg->nodeID, PUBACK, 0, PAN_ID, 0, 0);
            switch(rx_msg->topic)
            {
            case TEMPERATURE_ID:
                printf("[PAN Coordinator] Received PUBLISH message from %u, Topic:%u, Temperature, Data: %u\n", rx_msg->nodeID,rx_msg->topic,rx_msg->payload);
                handle_publish(rx_msg->nodeID, rx_msg->topic,rx_msg->qos,rx_msg->payload);
                break;
            case HUMIDITY_ID:
                printf("[PAN Coordinator] Received PUBLISH message from %u, Topic:%u, Humidity, Data: %u\n", rx_msg->nodeID,rx_msg->topic,rx_msg->payload);
                //handle_publish(rx_msg->nodeID, rx_msg->topic,rx_msg->qos,rx_msg->payload);
                break;
            case LUMINOSITY_ID:
                printf("[PAN Coordinator] Received PUBLISH message from %u, Topic:%u, Luminosity, Data: %u\n", rx_msg->nodeID,rx_msg->topic,rx_msg->payload);
                //handle_publish(rx_msg->nodeID, rx_msg->topic,rx_msg->qos,rx_msg->payload);
                break;
            default:
                printf("[PAN Coordinator] Received from Node %u an unkonwn topic: %u\n",rx_msg->nodeID,rx_msg->topic);
                break;
            }
        }
        return buf;
    }

    event void MessageTask.runTask(uint16_t dst, uint8_t msg_type, uint8_t qos, uint16_t nodeID, uint8_t topic, uint16_t payload){
            /*my_msg_t* pckt;
            pckt = call Packet.getPayload(&packet,sizeof(my_msg_t));
            pckt->msg_type = msg_type;
            pckt->qos = qos;
            pckt->nodeID = nodeID;
            pckt->topic = topic;
            pckt->payload = payload;*/
            //printf("[PAN Coordinator] DEBUG: dst: %u,msg_type:%u, nodeID: %u, topic: %u, payload:%u\n", dst,msg_type,nodeID,topic,payload);
            switch(msg_type)
            {
                case(CONNACK):
                    handle_connack(dst, qos);
                    break;
                case(SUBACK):
                    handle_suback(dst, qos);
                    break;
                /*case(PUBLISH):
                    if( call AMSend.send(dst, &packet, sizeof(my_msg_t)) == SUCCESS)
                    {
                        printf("[PAN Coordinator] Forward PUBLISH to Node %u\n", dst);
                    }else
                        printf("[PAN Coordinator] Fail to send PUBLISH to node %u\n", dst);
                    //handle_publish(dst, packet);
                    break;
                */case(PUBACK):
                    handle_puback(dst, qos);
                    break;
                default:
                    printf("[PAN Coordinator] Received bad msg type\n");
                    break;
            }
            global_packet = packet;

    }

    void handle_suback(uint16_t dst, uint8_t qos){
        my_msg_t* pckt;
        pckt = call Packet.getPayload(&suback_packet,sizeof(my_msg_t));
        pckt->msg_type = SUBACK;
        pckt->qos = qos;
        pckt->nodeID = PAN_ID;
        if( call AMSend.send(dst, &suback_packet, sizeof(my_msg_t)) == SUCCESS)
        {
            printf("[PAN Coordinator] Sent SUBACK to node %u\n", dst);
        }else{
            printf("[PAN Coordinator] Fail to send SUBACK to node %u\n", dst);
            //call MessageTask.postTask(dst,SUBACK,qos,PAN_ID,0,0);
        }
    }
    void handle_connack(uint16_t dst, uint8_t qos){
        my_msg_t* pckt;
        pckt = call Packet.getPayload(&connack_packet,sizeof(my_msg_t));
        pckt->msg_type = CONNACK;
        pckt->qos = qos;
        pckt->nodeID = PAN_ID;
        if( call AMSend.send(dst, &connack_packet, sizeof(my_msg_t)) == SUCCESS)
        {
            printf("[PAN Coordinator] Sent CONNACK to node %u\n", dst);
        }else{
            connected_nodes[dst - 1] = FALSE;
            printf("[PAN Coordinator] Fail to send CONNACK to node %u\n", dst);
            //call MessageTask.postTask(dst,SUBACK,qos,PAN_ID,0,0);
        }
    }
    void handle_puback(uint16_t dst, uint8_t qos){
        my_msg_t* pckt;
        pckt = call Packet.getPayload(&puback_packet,sizeof(my_msg_t));
        pckt->msg_type = PUBACK;
        pckt->qos = qos;
        pckt->nodeID = PAN_ID;
        if( call AMSend.send(dst, &puback_packet, sizeof(my_msg_t)) == SUCCESS)
        {
            printf("[PAN Coordinator] Sent PUBACK to Node %u\n", dst);
        }else
            printf("[PAN Coordinator] Fail to send PUBACK to node %u\n", dst);
    }

 /*   task void forwardPublishTask(){
         uint16_t i;
            switch(topic_rx)
            {
            case TEMPERATURE_ID:
                printf("[PAN Coordinator] Received publish message from %u, Topic:%u, Temperature, Data: %u\n", node_ids, topic_rx, payload_rx);
                for(i = 0; i < NNODE; i++)
                    if(sub_nodes_tmp[i])
                        handle_publish(i+1,topic_rx,payload_rx);
                        //printf("Node %u subscribed to topic Temperature\n", i + 1);
                break;
            case HUMIDITY_ID:
                printf("[PAN Coordinator] Received publish message from %u, Topic:%u, Humidity, Data: %u\n", node_ids, topic_rx, payload_rx);
                for(i = 0; i < NNODE; i++)
                    if(sub_nodes_hum[i])
                        handle_publish(i+1,topic_rx,payload_rx);
                        //printf("Node %u subscribed to topic Humidity\n", i + 1);
                break;
            case LUMINOSITY_ID:
                printf("[PAN Coordinator] Received publish message from %u, Topic:%u, Luminosity, Data: %u\n", node_ids, topic_rx, payload_rx);
                for(i = 0; i < NNODE; i++)
                    if(sub_nodes_lum[i])
                        handle_publish(i+1,topic_rx,payload_rx);
                        //printf("Node %u subscribed to topic Luminosity\n", i + 1);
                break;
           }
    }*/

   void handle_publish(uint16_t node_address, uint8_t topic, uint8_t qos, uint16_t payload) {
        uint16_t index;
        for(index = 0; index < NNODE; index++)
            if(sub_nodes_tmp[index] && index+1 != node_address){
                my_msg_t* pckt;
                node_address = index + 1;
                //call MessageTask.postTask(index+1,PUBLISH, 0, PAN_ID, rx_msg->topic, rx_msg->payload);
                printf("[PAN Coordinator] Publish forward to node :%u\n",node_address);
                pckt = call Packet.getPayload(&publish_packet,sizeof(my_msg_t));
                pckt->msg_type = PUBLISH;
                pckt->qos = qos;
                pckt->nodeID = node_address;
                pckt->topic = topic;
                pckt->payload = payload;
                if( call AMSend.send(node_address, &publish_packet, sizeof(my_msg_t)) == SUCCESS)
                {
                    printf("[PAN Coordinator] Sent publish to Node %u\n", node_address);
                }else
                    printf("[PAN Coordinator] Fail to send publish to node %u\n", node_address);
            }


    }

 /*   task void sendSubAckTask(){

        printf("[PAN Coordinator] Subscribe received from Node %u to topic %u\n",node_ids, topic_rx);
        pckt = call Packet.getPayload(&packet,sizeof(my_msg_t));
        pckt->msg_type = SUBACK;
        pckt->nodeID = PAN_ID;
        if( call AMSend.send(node_ids, &packet, sizeof(my_msg_t)) == SUCCESS)
        {
            printf("[PAN Coordinator] Sent Suback to node %u\n", node_ids);
        }else
            printf("[PAN Coordinator] Fail to send Suback to node %u\n", node_ids);
    }
    task void sendConnackTask(){

        printf("[PAN Coordinator] Connect received from node :%u\n",node_ids);
        pckt = call Packet.getPayload(&packet,sizeof(my_msg_t));
        pckt->msg_type = CONNACK;
        pckt->nodeID = PAN_ID;//AM_PAN_COORD_ADDR;
    	if( call AMSend.send(node_ids, &packet, sizeof(my_msg_t)) == SUCCESS)
    	{
    		printf("[PAN Coordinator] Sent Connack to node %u\n", node_ids);
    	}else{
            connected_nodes[node_ids - 1] = FALSE;
            printf("[PAN Coordinator] Fail to send Connack to node %u\n", node_ids);
        }
    }

 */   
    event void AMSend.sendDone(message_t* buf,error_t err) {
        //printf("DEBUG\n");
        if((&packet == buf || &connack_packet == buf || &suback_packet == buf)  && err == SUCCESS );
            //printf("[PAN Coordinator] Packet Sent\n");
        else if ( err != SUCCESS)
            printf("[PAN Coordinator] Packet NOT sent, failed\n");
    
        if ( call PacketAcknowledgements.wasAcked( buf ) );
          //printf("[PAN Coordinator] Packet acked!\n");
    }
}