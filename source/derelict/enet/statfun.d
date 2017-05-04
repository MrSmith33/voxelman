/*
 * Copyright (c) 2013 Derelict Developers
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met:
 *
 * * Redistributions of source code must retain the above copyright
 *   notice, this list of conditions and the following disclaimer.
 *
 * * Redistributions in binary form must reproduce the above copyright
 *   notice, this list of conditions and the following disclaimer in the
 *   documentation and/or other materials provided with the distribution.
 *
 * * Neither the names 'Derelict', 'DerelictILUT', nor the names of its contributors
 *   may be used to endorse or promote products derived from this software
 *   without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
 * TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 * LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 * NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */
module derelict.enet.statfun;

public import derelict.enet.types;

extern(C) @nogc nothrow
{
	// enet.h
	int enet_initialize();
	int enet_initialize_with_callbacks(ENetVersion version_, const ENetCallbacks * inits);
	void enet_deinitialize();
	ENetVersion enet_linked_version();
	enet_uint32 enet_time_get();
	void enet_time_set(enet_uint32);
	ENetSocket enet_socket_create(ENetSocketType);
	int enet_socket_bind(ENetSocket, const ENetAddress *);
	int enet_socket_get_address(ENetSocket, ENetAddress *);
	int enet_socket_listen(ENetSocket, int);
	ENetSocket enet_socket_accept(ENetSocket, ENetAddress *);
	int enet_socket_connect(ENetSocket, const ENetAddress *);
	int enet_socket_send(ENetSocket, const ENetAddress *, const ENetBuffer *, size_t);
	int enet_socket_receive(ENetSocket, ENetAddress *, ENetBuffer *, size_t);
	int enet_socket_wait(ENetSocket, enet_uint32 *, enet_uint32);
	int enet_socket_set_option(ENetSocket, ENetSocketOption, int);
	int enet_socket_get_option(ENetSocket, ENetSocketOption, int *);
	int enet_socket_shutdown(ENetSocket, ENetSocketShutdown);
	void enet_socket_destroy(ENetSocket);
	int enet_socketset_select(ENetSocket, ENetSocketSet *, ENetSocketSet *, enet_uint32);
	int enet_address_set_host(ENetAddress * address, const char * hostName);
	int enet_address_get_host_ip(const ENetAddress * address, char * hostName, size_t nameLength);
	int enet_address_get_host(const ENetAddress * address, char * hostName, size_t nameLength);
	ENetPacket * enet_packet_create(const void *, size_t, enet_uint32);
	void enet_packet_destroy(ENetPacket *);
	int enet_packet_resize (ENetPacket *, size_t);
	enet_uint32  enet_crc32(const ENetBuffer *, size_t);
	ENetHost * enet_host_create(const ENetAddress *, size_t, size_t, enet_uint32, enet_uint32);
	void enet_host_destroy(ENetHost *);
	ENetPeer * enet_host_connect(ENetHost *, const ENetAddress *, size_t, enet_uint32);
	int enet_host_check_events(ENetHost *, ENetEvent *);
	int enet_host_service(ENetHost *, ENetEvent *, enet_uint32);
	void enet_host_flush(ENetHost *);
	void enet_host_broadcast(ENetHost *, enet_uint8, ENetPacket *);
	void enet_host_compress(ENetHost *, const ENetCompressor *);
	int enet_host_compress_with_range_coder(ENetHost * host);
	void enet_host_channel_limit(ENetHost *, size_t);
	void enet_host_bandwidth_limit(ENetHost *, enet_uint32, enet_uint32);
	int enet_peer_send(ENetPeer *, enet_uint8, ENetPacket *);
	ENetPacket * enet_peer_receive(ENetPeer *, enet_uint8 * channelID);
	void enet_peer_ping(ENetPeer *);
	void enet_peer_ping_interval(ENetPeer *, enet_uint32);
	void enet_peer_timeout(ENetPeer *, enet_uint32, enet_uint32, enet_uint32);
	void enet_peer_reset(ENetPeer *);
	void enet_peer_disconnect(ENetPeer *, enet_uint32);
	void enet_peer_disconnect_now(ENetPeer *, enet_uint32);
	void enet_peer_disconnect_later(ENetPeer *, enet_uint32);
	void enet_peer_throttle_configure(ENetPeer *, enet_uint32, enet_uint32, enet_uint32);
	void * enet_range_coder_create();
	void   enet_range_coder_destroy(void *);
	size_t enet_range_coder_compress(void *, const ENetBuffer *, size_t, size_t, enet_uint8 *, size_t);
	size_t enet_range_coder_decompress(void *, const enet_uint8 *, size_t, enet_uint8 *, size_t);
}
