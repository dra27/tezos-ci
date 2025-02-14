type t

val make : unit -> t

val update_state :
  t -> id:string Current.t -> Lib.Task.subtask_node Current.t -> unit Current.t

val routes : t -> Current_web.Resource.t Routes.route list
