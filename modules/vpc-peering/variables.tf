variable "name" {
  description = "Name tag for the peering connection."
  type        = string
}

variable "requester_vpc_id" {
  description = "Requester VPC ID."
  type        = string
}

variable "accepter_vpc_id" {
  description = "Accepter VPC ID (same account/region)."
  type        = string
}

variable "requester_cidr" {
  description = "Requester VPC CIDR (routed on the accepter side)."
  type        = string
}

variable "accepter_cidr" {
  description = "Accepter VPC CIDR (routed on the requester side)."
  type        = string
}

variable "requester_route_table_ids" {
  description = "Route tables in the requester VPC that should reach the peer."
  type        = list(string)
}

variable "accepter_route_table_ids" {
  description = "Route tables in the accepter VPC that should reach the peer."
  type        = list(string)
}

variable "tags" {
  description = "Tags applied to the peering connection."
  type        = map(string)
  default     = {}
}
