#include "utils.h"
#include "printf.h"

#define NNODE 8
#define PAN_ID TOS_NODE_ID
#define RESEND_PUB 20

module PANCoordinatorC {
	uses {
		interface Boot;
		interface AMSend;
        interface SplitControl;
        interface Receive;
        interface PacketAcknowledgements;
        interface Packet;
        interface MessageTask;
        interface Timer<TMilli> as TimeOutTimer;
	}
}	implementation {
    bool connected_nodes[NNODE];
    bool sub_nodes_tmp[NNODE];
    bool sub_nodes_hum[NNODE];
    bool sub_nodes_lum[NNODE];
    bool publish_list[NNODE];
    bool qos_required[NNODE];
    bool ready_to_receive_publish = TRUE;
    uint8_t qos_levels_tmp[NNODE];
    uint8_t qos_levels_hum[NNODE];
    uint8_t qos_levels_lum[NNODE];

    uint16_t node_publishing;
    uint8_t topic_publishing;

    message_t connack_packet;
    message_t suback_packet;
    message_t publish_packet;
    message_t puback_packet;
    message_t packet;

	void handle_publish(uint16_t node_address, uint8_t topic, uint8_t qos, uint16_t payload);
    void handle_suback(uint16_t dst, uint8_t qos, uint8_t topic);
    void handle_connack(uint16_t dst, uint8_t qos);
    void handle_puback(uint16_t dst, uint8_t qos);
    task void publishTask();
    void build_List(bool * actual_list, uint8_t * qos_levels, uint16_t node_address);

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

    /********Receive interface*********/

    event message_t* Receive.receive(message_t* buf, void* payload, uint8_t len){

    	my_msg_t* rx_msg = (my_msg_t*)payload;
    	//printf("LENGTH: %u\n", len);
    	if(rx_msg->msg_type == CONNECT){
            if(!connected_nodes[rx_msg->nodeID - 1]){
                connected_nodes[rx_msg->nodeID - 1] = TRUE;
                printf("[PAN Coordinator] CONNECT received from node :%u, MY ID: %u\n",rx_msg->nodeID, PAN_ID);
                call MessageTask.postTask(rx_msg->nodeID, CONNACK, rx_msg->qos, PAN_ID, 0, 0);
            }
            else
                printf("[PAN Coordinator] Received CONNECT message from %u but already connected\n",rx_msg->nodeID);
        }else if (rx_msg->msg_type == SUBSCRIBE){
            switch(rx_msg->topic)
            {
            case TEMPERATURE_ID:
                sub_nodes_tmp[rx_msg->nodeID - 1] = TRUE;
                qos_levels_tmp[rx_msg->nodeID - 1] = rx_msg->qos;
                break;
            case HUMIDITY_ID:
                sub_nodes_hum[rx_msg->nodeID - 1] = TRUE;
                qos_levels_hum[rx_msg->nodeID - 1] = rx_msg->qos;
                break;
            case LUMINOSITY_ID:
                sub_nodes_lum[rx_msg->nodeID - 1] = TRUE;
                qos_levels_lum[rx_msg->nodeID - 1] = rx_msg->qos;
                break;
            default:
                printf("[PAN Coordinator] Bad topic received for subscribe\n");
                break;
            }
            printf("[PAN Coordinator] SUBSCRIBE received from Node %u to Topic %u with QoS:%u\n",
                rx_msg->nodeID, rx_msg->topic, rx_msg->qos);

            call MessageTask.postTask(rx_msg->nodeID, SUBACK, rx_msg->qos, PAN_ID, rx_msg->topic, 0);

        }else if (rx_msg->msg_type == PUBLISH){
            //se sto già pubblicando o ricevo un nuovo dato dal medesimo sensore sullo stesso topic che
            // sta pubblicando mando dato aggiornato
            if(ready_to_receive_publish || (rx_msg->nodeID == node_publishing && rx_msg->topic == topic_publishing)){
                ready_to_receive_publish = FALSE;
                if(rx_msg->topic != TEMPERATURE_ID && rx_msg->topic != HUMIDITY_ID && rx_msg->topic != LUMINOSITY_ID)
                    printf("[PAN Coordinator] Received from Node %u an unkonwn topic: %u\n",rx_msg->nodeID,rx_msg->topic);
                else{
                    printf("[PAN Coordinator] Received PUBLISH message from %u, Qos: %u, Topic:%u, Data: %u\n",
                            rx_msg->nodeID, rx_msg->qos, rx_msg->topic,rx_msg->payload);
                    node_publishing = rx_msg->nodeID;
                    topic_publishing = rx_msg->topic;
                    if(rx_msg->qos)
                        call MessageTask.postTask(rx_msg->nodeID, PUBACK, 0, PAN_ID, 0, 0);
                }
                handle_publish(rx_msg->nodeID, rx_msg->topic,rx_msg->qos,rx_msg->payload);
            }else
                printf("[PAN Coordinator] Discarded Publish received from Node %u, waiting for complete forwarding\n", rx_msg->nodeID);

        }else if (rx_msg->msg_type == PUBACK){
            printf("[PAN Coordinator] Received PUBACK message from Node %u\n", rx_msg->nodeID);
            if(publish_list[rx_msg->nodeID - 1])
                publish_list[rx_msg->nodeID - 1] = FALSE;
        }
        return buf;
    }

/******** Asynchronous send of messages in order to answer CONNECT,SUBSCRIBE and PUBLISH ***********/
    event void MessageTask.runTask(uint16_t dst, uint8_t msg_type, uint8_t qos, uint16_t nodeID, uint8_t topic, uint16_t payload){
            //printf("[PAN Coordinator] DEBUG: dst: %u,msg_type:%u, nodeID: %u, topic: %u, payload:%u\n", dst,msg_type,nodeID,topic,payload);
            switch(msg_type)
            {
                case(CONNACK):
                    handle_connack(dst, qos);
                    break;
                case(SUBACK):
                    handle_suback(dst, qos, topic);
                    break;
                case(PUBACK):
                    handle_puback(dst, qos);
                    break;
                default:
                    printf("[PAN Coordinator] Received bad msg type\n");
                    break;
            }

    }
/***** Creation and send of a SUBACK message*********/
    void handle_suback(uint16_t dst, uint8_t qos, uint8_t topic){
        my_msg_t* pckt;
        pckt = call Packet.getPayload(&suback_packet,sizeof(my_msg_t));
        pckt->msg_type = SUBACK;
        pckt->qos = qos;
        pckt->topic = topic;
        pckt->nodeID = PAN_ID;
        if( call AMSend.send(dst, &suback_packet, sizeof(my_msg_t)) == SUCCESS)
        {
            printf("[PAN Coordinator] Sent SUBACK to node %u for Topic:%u\n", dst, topic);
        }else{
            printf("[PAN Coordinator] Fail to send SUBACK to node %u for Topic %u\n", dst, topic);
        }
    }

/*********** Creation and send of a CONNACK message*****/
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
        }
    }

/********* Creation and send of a PUBACK message******/
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
/******* Creation and forward of a PUBLISH message**********/
   void handle_publish(uint16_t node_address, uint8_t topic, uint8_t qos, uint16_t payload) {
        my_msg_t* tx_pub_pckt;
        tx_pub_pckt = call Packet.getPayload(&publish_packet,sizeof(my_msg_t));
        tx_pub_pckt->msg_type = PUBLISH;
        tx_pub_pckt->qos = qos;
        tx_pub_pckt->nodeID = node_address;
        tx_pub_pckt->topic = topic;
        tx_pub_pckt->payload = payload;

        switch(topic)
        {
        case TEMPERATURE_ID:
            build_List(sub_nodes_tmp, qos_levels_tmp, node_address);
            break;
        case HUMIDITY_ID:
            build_List(sub_nodes_hum, qos_levels_hum, node_address);
            break;
        case LUMINOSITY_ID:
            build_List(sub_nodes_lum, qos_levels_lum, node_address);
            break;
        default:
            return;
        }
        call TimeOutTimer.startPeriodic(RESEND_PUB);
    }

/*****Function to build the needed lists for the topic and for the required QoS*******/
    void build_List(bool * actual_list, uint8_t* qos_levels, uint16_t node_address){
        uint16_t index;
        for(index = 0; index < NNODE; index++){
            if(actual_list[index] && index+1 != node_address){
                publish_list[index] = TRUE;
                if( qos_levels[index] == 1)
                    qos_required[index] = TRUE;
                else
                    qos_required[index] = FALSE;
            }
        }
    }

/****** Send Done handle*******/
    event void AMSend.sendDone(message_t* buf,error_t err) {
        //printf("DEBUG\n");
        if((&packet == buf || &connack_packet == buf || &suback_packet == buf || &puback_packet == buf || &publish_packet == buf)  && err == SUCCESS ){
            ;//printf("[PAN Coordinator] Packet Sent\n");
        }
        else if ( err != SUCCESS)
            printf("[PAN Coordinator] Packet NOT sent, failed\n");
    
        if ( call PacketAcknowledgements.wasAcked( buf ) );
          //printf("[PAN Coordinator] Packet acked!\n");
    }
/******* Time Out for forward at regular intervals the PUBLISH message****/
    event void TimeOutTimer.fired(){
        post publishTask();
    }
/****** Effective Forward of the PUBLISH message to the right node with check of Qos******/
    task void publishTask(){
        uint16_t index;
        for(index = 0; index < NNODE; index++){
            if(publish_list[index] == TRUE){
                printf("[PAN Coordinator] Publish forward to node :%u\n",index + 1);

                if( call AMSend.send(index + 1, &publish_packet, sizeof(my_msg_t)) == SUCCESS)
                {
                    printf("[PAN Coordinator] Sent publish to Node %u\n", index + 1);
                    if(!qos_required[index])
                        publish_list[index] = FALSE;
                }else
                    printf("[PAN Coordinator] Fail to send publish to node %u\n", index + 1);
            break;
            }

        }
        if(index == NNODE){
            printf("[PAN Coordinator] Finished to forward publish message to subcribed nodes\n");
            ready_to_receive_publish = TRUE;
            node_publishing = 0;
            topic_publishing = 4;
            call TimeOutTimer.stop();
        }
    }
}