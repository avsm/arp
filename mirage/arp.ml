(*
 * Copyright (c) 2010-2011 Anil Madhavapeddy <anil@recoil.org>
 * Copyright (c) 2016 Hannes Mehnert <hannes@mehnert.org>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *
 *)

open Lwt.Infix

let logsrc = Logs.Src.create "ARP" ~doc:"Mirage ARP handler"

module Make (Ethif : Mirage_protocols_lwt.ETHIF) (Time : Mirage_time_lwt.S) = struct

  type 'a io = 'a Lwt.t
  type ipaddr = Ipaddr.V4.t
  type macaddr = Macaddr.t
  type error = Mirage_protocols.Arp.error
  type buffer = Cstruct.t
  type repr = ((macaddr, error) result Lwt.t * (macaddr, error) result Lwt.u) Arp_handler.t
  type t = {
    mutable state : repr ;
    ethif : Ethif.t ;
    mutable ticking : bool ;
  }

  let pp_error = Mirage_protocols.Arp.pp_error

  let probe_repeat_delay = Duration.of_ms 1500 (* per rfc5227, 2s >= probe_repeat_delay >= 1s *)

  let output t (buf, destination) =
    let ethif_packet = Ethernet_packet.(Marshal.make_cstruct {
        source = Arp_handler.mac t.state;
        destination;
        ethertype = Ethernet_wire.ARP;
      }) in
    Ethif.writev t.ethif [ethif_packet ; buf] >|= function
    | Ok () -> ()
    | Error e ->
      match Arp_packet.decode buf with
      | Ok p ->
        Logs.warn ~src:logsrc
          (fun m -> m "error %a while outputting packet %a to %a"
              Ethif.pp_error e Arp_packet.pp p Macaddr.pp destination)
      | Error ae ->
        Logs.warn ~src:logsrc
          (fun m -> m "error %a while outputing packet, and failing to parse our output %a"
              Ethif.pp_error e Arp_packet.pp_error ae)

  let rec tick t () =
    if t.ticking then
      Time.sleep_ns probe_repeat_delay >>= fun () ->
      let state, requests, timeouts = Arp_handler.tick t.state in
      t.state <- state ;
      Lwt_list.iter_p (output t) requests >>= fun () ->
      List.iter (fun (_, u) -> Lwt.wakeup u (Error `Timeout)) timeouts ;
      tick t ()
    else
      Lwt.return_unit

  let to_repr t = Lwt.return t.state

  let pp = Arp_handler.pp

  let input t frame =
    let state, out, wake = Arp_handler.input t.state frame in
    t.state <- state ;
    (match out with
     | None -> Lwt.return_unit
     | Some pkt -> output t pkt) >|= fun () ->
    match wake with
    | None -> ()
    | Some (mac, (_, u)) -> Lwt.wakeup u (Ok mac)

  let get_ips t = Arp_handler.ips t.state

  let create ?ipaddr t =
    let mac = Arp_handler.mac t.state in
    let state, out = Arp_handler.create ~logsrc ?ipaddr mac in
    t.state <- state ;
    match out with
    | None -> Lwt.return_unit
    | Some x -> output t x

  let add_ip t ipaddr =
    match Arp_handler.ips t.state with
    | [] -> create ~ipaddr t
    | _ ->
      let state, out, wake = Arp_handler.alias t.state ipaddr in
      t.state <- state ;
      output t out >|= fun () ->
      match wake with
      | None -> ()
      | Some (_, u) -> Lwt.wakeup u (Ok (Arp_handler.mac t.state))

  let init_empty mac =
    let state, _ = Arp_handler.create ~logsrc mac in
    state

  let set_ips t = function
    | [] ->
      let mac = Arp_handler.mac t.state in
      let state = init_empty mac in
      t.state <- state ;
      Lwt.return_unit
    | ipaddr::xs ->
      create ~ipaddr t >>= fun () ->
      Lwt_list.iter_s (add_ip t) xs

  let remove_ip t ip =
    let state = Arp_handler.remove t.state ip in
    t.state <- state ;
    Lwt.return_unit

  let query t ip =
    let merge = function
      | None -> MProf.Trace.named_wait "ARP response"
      | Some a -> a
    in
    let state, res = Arp_handler.query t.state ip merge in
    t.state <- state ;
    match res with
    | Arp_handler.RequestWait (pkt, (tr, _)) -> output t pkt >>= fun () -> tr
    | Arp_handler.Wait (t, _) -> t
    | Arp_handler.Mac m -> Lwt.return (Ok m)

  let connect ethif =
    let mac = Ethif.mac ethif in
    let state = init_empty mac in
    let t = { ethif; state; ticking = true} in
    Lwt.async (tick t);
    Lwt.return t

  let disconnect t =
    t.ticking <- false ;
    Lwt.return_unit
end
