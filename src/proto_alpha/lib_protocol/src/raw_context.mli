(**************************************************************************)
(*                                                                        *)
(*    Copyright (c) 2014 - 2018.                                          *)
(*    Dynamic Ledger Solutions, Inc. <contact@tezos.com>                  *)
(*                                                                        *)
(*    All rights reserved. No warranty, explicit or implicit, provided.   *)
(*                                                                        *)
(**************************************************************************)

(** {1 Errors} ****************************************************************)

(** An internal storage error that should not happen *)
type storage_error =
  | Incompatible_protocol_version of string
  | Missing_key of string list * [`Get | `Set | `Del | `Copy]
  | Existing_key of string list
  | Corrupted_data of string list

type error += Storage_error of storage_error
type error += Failed_to_parse_parameter of MBytes.t
type error += Failed_to_decode_parameter of Data_encoding.json * string

val storage_error: storage_error -> 'a tzresult Lwt.t

(** {1 Abstract Context} **************************************************)

(** Abstract view of the context.
    Includes a handle to the functional key-value database
    ({!Context.t}) along with some in-memory values (gas, etc.). *)
type t
type context = t
type root_context = t

(** Retrieves the state of the database and gives its abstract view.
    It also returns wether this is the first block validated
    with this version of the protocol. *)
val prepare:
  level: Int32.t ->
  timestamp: Time.t ->
  fitness: Fitness.t ->
  Context.t -> context tzresult Lwt.t

val prepare_first_block:
  level:int32 ->
  timestamp:Time.t ->
  fitness:Fitness.t ->
  Context.t -> (Parameters_repr.t * context) tzresult Lwt.t

val activate: context -> Protocol_hash.t -> t Lwt.t
val fork_test_chain: context -> Protocol_hash.t -> Time.t -> t Lwt.t

val register_resolvers:
  'a Base58.encoding -> (context -> string -> 'a list Lwt.t) -> unit

(** Returns the state of the database resulting of operations on its
    abstract view *)
val recover: context -> Context.t

val current_level: context -> Level_repr.t
val current_timestamp: context -> Time.t

val current_fitness: context -> Int64.t
val set_current_fitness: context -> Int64.t -> t

val constants: context -> Constants_repr.parametric
val patch_constants:
  context ->
  (Constants_repr.parametric -> Constants_repr.parametric) ->
  context Lwt.t
val first_level: context -> Raw_level_repr.t

val add_fees: context -> Tez_repr.t -> context tzresult Lwt.t
val add_rewards: context -> Tez_repr.t -> context tzresult Lwt.t

val get_fees: context -> Tez_repr.t
val get_rewards: context -> Tez_repr.t

type error += Gas_limit_too_high (* `Permanent *)

val set_gas_limit: t -> Z.t -> t tzresult
val set_gas_unlimited: t -> t
val gas_level: t -> Gas_limit_repr.t
val block_gas_level: t -> Z.t

type error += Storage_limit_too_high (* `Permanent *)

val set_storage_limit: t -> Int64.t -> t tzresult
val set_storage_unlimited: t -> t

type error += Undefined_operation_nonce (* `Permanent *)

val init_origination_nonce: t -> Operation_hash.t -> t
val origination_nonce: t -> Contract_repr.origination_nonce tzresult
val increment_origination_nonce: t -> (t * Contract_repr.origination_nonce) tzresult
val unset_origination_nonce: t -> t

(** {1 Generic accessors} *************************************************)

type key = string list

type value = MBytes.t

(** All context manipulation functions. This signature is included
    as-is for direct context accesses, and used in {!Storage_functors}
    to provide restricted views to the context. *)
module type T = sig

  type t
  type context = t

  (** Tells if the key is already defined as a value. *)
  val mem: context -> key -> bool Lwt.t

  (** Tells if the key is already defined as a directory. *)
  val dir_mem: context -> key -> bool Lwt.t

  (** Retrieve the value from the storage bucket ; returns a
      {!Storage_error Missing_key} if the key is not set. *)
  val get: context -> key -> value tzresult Lwt.t

  (** Retrieves the value from the storage bucket ; returns [None] if
      the data is not initialized. *)
  val get_option: context -> key -> value option Lwt.t

  (** Allocates the storage bucket and initializes it ; returns a
      {!Storage_error Existing_key} if the bucket exists. *)
  val init: context -> key -> value -> context tzresult Lwt.t

  (** Updates the content of the bucket ; returns a {!Storage_error
      Missing_key} if the value does not exists. *)
  val set: context -> key -> value -> context tzresult Lwt.t

  (** Allocates the data and initializes it with a value ; just
      updates it if the bucket exists. *)
  val init_set: context -> key -> value -> context Lwt.t

  (** When the value is [Some v], allocates the data and initializes
      it with [v] ; just updates it if the bucket exists. When the
      valus is [None], delete the storage bucket when the value ; does
      nothing if the bucket does not exists. *)
  val set_option: context -> key -> value option -> context Lwt.t

  (** Delete the storage bucket ; returns a {!Storage_error
      Missing_key} if the bucket does not exists. *)
  val delete: context -> key -> context tzresult Lwt.t

  (** Removes the storage bucket and its contents ; does nothing if the
      bucket does not exists. *)
  val remove: context -> key -> context Lwt.t

  (** Recursively removes all the storage buckets and contents ; does
      nothing if no bucket exists. *)
  val remove_rec: context -> key -> context Lwt.t

  val copy: context -> from:key -> to_:key -> context tzresult Lwt.t

  (** Iterator on all the items of a given directory. *)
  val fold:
    context -> key -> init:'a ->
    f:([ `Key of key | `Dir of key ] -> 'a -> 'a Lwt.t) ->
    'a Lwt.t

  (** Recursively list all subkeys of a given key. *)
  val keys: context -> key -> key list Lwt.t

  (** Recursive iterator on all the subkeys of a given key. *)
  val fold_keys:
    context -> key -> init:'a -> f:(key -> 'a -> 'a Lwt.t) -> 'a Lwt.t

  (** Internally used in {!Storage_functors} to escape from a view. *)
  val project: context -> root_context

  (** Internally used in {!Storage_functors} to retrieve a full key
      from partial key relative a view. *)
  val absolute_key: context -> key -> key

  (** Internally used in {!Storage_functors} to consume gas from
      within a view. *)
  val consume_gas: context -> Gas_limit_repr.cost -> context tzresult

  (** Internally used in {!Storage_functors} to consume storage from
      within a view. *)
  val record_bytes_stored: context -> Int64.t -> context tzresult

end

include T with type t := t and type context := context

val record_endorsement: context -> int -> context
val endorsement_already_recorded: context -> int -> bool

(** Initialize the local nonce used for preventing a script to
    duplicate an internal operation to replay it. *)
val reset_internal_nonce: context -> context

(** Increments the internal operation nonce. *)
val fresh_internal_nonce: context -> (context * int) tzresult

(** Mark an internal operation nonce as taken. *)
val record_internal_nonce: context -> int -> context

(** Check is the internal operation nonce has been taken. *)
val internal_nonce_already_recorded: context -> int -> bool
