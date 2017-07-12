#include "utils.h"
#include "printf.h"

module PANCoordinatorC {
	uses {
		interface Boot;
		interface AMSend;
        interface SplitControl;
        interface Receive;
        interface PacketAcknowledgements;
        interface Packet;
	}
}	implementation {
	message_t packet;
    my_msg_t * pckt;
    uint8_t node_ids;
	void handle_connect(uint8_t node_id);
	task void sendConnack();


	event void Boot.booted()
    {
        call SplitControl.start();
    }

    event void SplitControl.startDone(error_t err)
    {
        if(err == SUCCESS)
        {
            printf("[PAN Coordinator] Started!\n");
        }
        else
        {
            call SplitControl.start();
        }
    }

    event void SplitControl.stopDone(error_t err) {}

    event message_t* Receive.receive(message_t* buf, void* payload, uint8_t len){

    	my_msg_t* rx_msg = (my_msg_t*)payload;
    	
    	if(rx_msg->msg_type == CONNECT)
    		handle_connect(rx_msg->nodeID);
        return buf;
    }

    void handle_connect(uint8_t node_id){

    	printf("[PAN Coordinator] Connect received from node :%u\n",node_id);
        node_ids = node_id;
    	post sendConnack();

    }

    task void sendConnack(){
    	pckt = call Packet.getPayload(&packet,sizeof(my_msg_t));
    	pckt->msg_type = CONNACK;
    	pckt->nodeID = PAN;

    	if( call AMSend.send(node_ids, &packet, sizeof(my_msg_t)) == SUCCESS)
    	{
    		printf("[PAN Coordinator] Sent Connack to node %u\n", node_ids);
    	}
    }

    
    event void AMSend.sendDone(message_t* buf,error_t err) {}
}