import * as lib from "@clusterio/lib";
import { BaseInstancePlugin } from "@clusterio/host";
import { PluginExampleEvent, PluginExampleRequest } from "./messages";

export type ZoneConfig = Record<string, ZoneDefinition>;

export type ZoneDefinition = {
	// Name of the zone
	name: string,
	// Linking target
	link: ZoneTarget | null,
	// Whether enabled
	enabled: boolean,
	// Surface on this host
	surface: string,
	x1: number,
	y1: number,
	x2 : number
	y2: number
};

export type ZoneTarget = {
	instance: string
	name: string
}

type ZoneAddIPC = {
	name: string,
	surface: string,
	x1: number,
	y1: number,
	x2 : number
	y2: number
}

type ZoneDeleteIPC = {
	name: string
}

type ZoneLinkIPC = {
	name: string
	instance: string
	target_name: string
}

type ZoneStatusIPC = {
	name: string
	enabled: boolean
}

export class InstancePlugin extends BaseInstancePlugin {
	async init() {
		this.instance.handle(PluginExampleEvent, this.handlePluginExampleEvent.bind(this));
		this.instance.handle(PluginExampleRequest, this.handlePluginExampleRequest.bind(this));

		this.instance.server.handle("clusterio_trains_zone_add", this.handleZoneAddIPC.bind(this));
		this.instance.server.handle("clusterio_trains_zone_delete", this.handleZoneDeleteIPC.bind(this));
		this.instance.server.handle("clusterio_trains_zone_link", this.handleZoneLinkIPC.bind(this));
		this.instance.server.handle("clusterio_trains_zone_status", this.handleZoneStatusIPC.bind(this));
	}

	async onInstanceConfigFieldChanged(field: string, curr: unknown, prev: unknown) {
		this.logger.info(`instance::onInstanceConfigFieldChanged ${field}`);
	}

	async onStart() {
		let zones = this.instance.config.get("clusterio_trains.zones");
		let data = JSON.stringify(zones);
		this.logger.info(`Uploading zone data ${data}`);
		this.sendRcon(`/c clusterio_trains.sync_zones("${lib.escapeString(data)}")`);
	}

	async onStop() {
		this.logger.info("instance::onStop");
	}

	async onPlayerEvent(event: lib.PlayerEvent) {
		this.logger.info(`onPlayerEvent::onPlayerEvent ${JSON.stringify(event)}`);
		// this.sendRcon("/sc clusterio_trains.foo()");
	}

	async handlePluginExampleEvent(event: PluginExampleEvent) {
		this.logger.info(JSON.stringify(event));
	}

	async handlePluginExampleRequest(request: PluginExampleRequest) {
		this.logger.info(JSON.stringify(request));
		return {
			myResponseString: request.myString,
			myResponseNumbers: request.myNumberArray,
		};
	}

	async handleZoneAddIPC(event: ZoneAddIPC) {
		this.logger.info(`Received zone add ${JSON.stringify(event)}`);
		// Check validity
		if (event.x1 > event.x2 || event.y1 > event.y2 || event.name.length === 0)
			return;
		this.logger.info(JSON.stringify(event));
		const zones = this.instance.config.get("clusterio_trains.zones");
		for(const key in zones) {
			if (key == event.name)
				// Duplicate name
				return;
			let zone = zones[key];
			if (!(zone.x1 > event.x2 || zone.x2 < event.x1 || zone.y1 > event.y1 || zone.y2 < event.y2))
				// Overlap
				return;
		}
		let newZones = {...zones};
		let newZone = {...event,
			link: null,
			enabled: false // Can't enable an unlinked zone
		}
		newZones[event.name] = newZone;
		this.instance.config.set("clusterio_trains.zones", newZones);
		this.logger.info(`Created zone ${event.name}`);
		await this.syncZone(event.name);
		this.logger.info(`Finished creating zone ${event.name}`);
	}

	async handleZoneDeleteIPC(event: ZoneDeleteIPC) {
		const zones = this.instance.config.get("clusterio_trains.zones");
		if (event.name in zones) {
			let newZones = {...zones};
			delete newZones[event.name];
			this.instance.config.set("clusterio_trains.zones", newZones);
			this.logger.info(`Deleting zone ${event.name}`);
			await this.syncZone(event.name);
		} else {
			this.logger.info(`Unknown zone ${event.name}`);
			return;
		}
	}

	async handleZoneStatusIPC(event : ZoneStatusIPC) {
		const zones = this.instance.config.get("clusterio_trains.zones");
		if(event.name in zones) {
			let newZones = {...zones};
			zones[event.name].enabled = event.enabled;
			this.instance.config.set("clusterio_trains.zones", newZones);
			this.logger.info(`Setting zone ${event.name} status ${event.enabled}`);
			await this.syncZone(event.name);
		} else {
			this.logger.info(`Unknown zone ${event.name}`);
		}
	}

	async handleZoneLinkIPC(event: ZoneLinkIPC) {
		const zones = this.instance.config.get("clusterio_trains.zones");
		if(event.name in zones) {
			let newZones = {...zones};
			
			zones[event.name].link = {instance: event.instance, name: event.target_name};
			this.instance.config.set("clusterio_trains.zones", newZones);
			this.logger.info(`Linking zone ${event.name} to ${event.instance}:${event.target_name}`);
			await this.syncZone(event.name);
		} else {
			this.logger.info(`Unknown zone ${event.name}`);
		}
	}

	async syncZone(name: string) {
		const zones = this.instance.config.get("clusterio_trains.zones");
		this.logger.info(`Sending data about zone ${name}`)
		if (name in zones) {
			// Update
			let data = lib.escapeString(JSON.stringify(zones[name]));
			this.sendRcon(`/c clusterio_trains.sync_zone("${name}", "${data}")`);
		} else {
			// Delete
			this.sendRcon(`/c clusterio_trains.sync_zone("${name}")`);
		}
	}
}
