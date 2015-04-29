defmodule Exrethinkdb.Query do
  defmodule Q do
    defstruct query: nil
  end

  def make_array(array), do:  %Q{query: [2, array]}
  def db(name), do:           %Q{query: [14, [name]]}
  def table(name), do:        %Q{query: [15, [name]]}
  def table(query, name), do: %Q{query: [15, [query, name]]}

  def db_create(name), do:    %Q{query: [57, [name]]}
  def db_drop(name), do:      %Q{query: [58, [name]]}
  def db_list, do:            %Q{query: [59]}

  def table_create(db_query, name, options), do: %Q{query: [60, [db_query, name], options]}
  def table_create(name, options = %{}), do: %Q{query: [60, [name], options]}
  def table_create(db_query, name), do: %Q{query: [60, [db_query, name]]}
  def table_create(name), do: %Q{query: [60, [name]]}

  def table_drop(db_query, name), do:   %Q{query: [61, [db_query, name]]}
  def table_drop(name), do:   %Q{query: [61, [name]]}

  def table_list(db_query), do: %Q{query: [62, [db_query]]}
  def table_list, do: %Q{query: [62]}

  def filter(query, f) when is_function(f), do: %Q{query: [39, [query, func(f)]]}
  def filter(query, filter), do: %Q{query: [39, [query, filter]]}

  def get(query, id), do: %Q{query: [16, [query,  id]]}
  def get_all(query, id, options \\ %{}), do: %Q{query: [78, [query,  id], options]}

  def between(_lower, _upper, _options), do: raise "between is not yet implemented"

  def insert(table, object, options \\ %{})
  def insert(table, object, options) when is_list(object), do: %Q{query: [56, [table, make_array(object)], options]}
  def insert(table, object, options), do: %Q{query: [56, [table, object], options]}

  def update(selection, object, options \\ %{}), do: %Q{query: [53, [selection, object], options]}
  def replace(selection, object, options \\ %{}), do: %Q{query: [55, [selection, object], options]}
  def delete(selection, options \\ %{}), do: %Q{query: [54, [selection], options]}

  def changes(selection), do: %Q{query: [152, [selection]]}

  def pluck(selection, fields), do: %Q{query: [33, [selection | fields]]}
  def without(selection, fields), do: %Q{query: [34, [selection | fields]]}
  def distinct(sequence), do: %Q{query: [42, [sequence]]}
  def count(sequence), do: %Q{query: [43, [sequence]]}
  def has_fields(sequence, fields), do:  %Q{query: [32, [sequence, make_array(fields)]]}

  def keys(object), do: %Q{query: [94, [object]]}

  def merge(objects), do: %Q{query: [35, objects]}

  def map(sequence, f), do: %Q{query: [38, [sequence, func(f)]]}

  # standard multi arg arithmetic operations
  [
    {:add, 24},
    {:sub, 25},
    {:mul, 26},
    {:div, 27},
    {:eq, 17},
    {:ne, 18},
    {:lt, 19},
    {:le, 20},
    {:gt, 21},
    {:ge, 22}
  ] |> Enum.map fn ({op, opcode}) ->
    def unquote(op)(numA, numB), do: %Q{query: [unquote(opcode), [numA, numB]]}
    def unquote(op)(nums) when is_list(nums), do: %Q{query: [unquote(opcode), nums]}
  end

  # arithmetic unary ops
  [
    {:not, 23},
    # Not supported yet
    # {:floor, 183},
    # {:ceil, 184},
    # {:round, 185}
  ] |> Enum.map fn ({op, opcode}) ->
    def unquote(op)(val), do: %Q{query: [unquote(opcode), [val]]}
  end

  # arithmetic ops that don't fit into the above
  def mod(numA, numB), do: %Q{query: [28, [numA, numB]]}

  def func(f) when is_function(f) do
    {_, arity} = :erlang.fun_info(f, :arity)

    args = Enum.map(1..arity, fn _ -> make_ref end)
    params = Enum.map(args, &var/1)
    res = case apply(f, params) do
      x when is_list(x) -> make_array(x)
      x -> x
    end
    %Q{query: [69, [[2, args], res]]}
  end

  def var(val), do: %Q{query: [10, [val]]}
  def bracket(obj, key), do: %Q{query: [170, [obj, key]]}

  def prepare(query) do
    %{query: prepared_query} = prepare(query, %{query: [], vars: {0, %{}}})
    prepared_query
  end
  def prepare(%Exrethinkdb.Query.Q{query: query}, acc), do: prepare(query, acc)
  def prepare([h | t], %{query: query, vars: vars}) do
    %{query: new_query, vars: new_vars} = prepare(h, %{query: [], vars: vars})
    prepare(t, %{query: query ++ [new_query], vars: new_vars})
  end
  def prepare([], acc) do
    acc
  end
  def prepare(ref, %{query: query, vars: {max, map}}) when is_reference(ref) do
    case Dict.get(map, ref) do
      nil ->
        %{
          query: query ++ (max + 1),
          vars: {max + 1, Dict.put_new(map, ref, max + 1)}
        }
      x ->
        %{
          query: query ++ x,
          vars: {max, map}
        }
    end
  end
  def prepare(el, %{query: query, vars: vars}) do
    %{query: query ++ el, vars: vars}
  end
end
defimpl Poison.Encoder, for: Exrethinkdb.Query.Q do
  def encode(%{query: query}, options) do
    Poison.Encoder.encode(query, options)
  end
end
defimpl Access, for: Exrethinkdb.Query.Q do
  def get(%{query: query}, term) do
    Exrethinkdb.Query.bracket(query, term)
  end

  def get_and_update(_,_,_), do: raise "get_and_update not supported"
end
