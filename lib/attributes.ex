defmodule Attributes do
  @moduledoc false

  def get(bound_variables, reportable_attr_keys, result \\ nil) do
    bound_variables
    |> take_attrs(reportable_attr_keys)
    |> maybe_add_result(reportable_attr_keys, result)
    |> remove_underscores()
    |> Enum.into([])
  end

  defp take_attrs(bound_variables, attr_keys) do
    {keys, nested_keys} = Enum.split_with(attr_keys, &is_atom/1)

    attrs = Keyword.take(bound_variables, keys)
    nested_attrs = take_nested_attrs(bound_variables, nested_keys)

    Keyword.merge(nested_attrs, attrs)
  end

  defp take_nested_attrs(bound_variables, nested_keys) do
    nested_keys
    |> Enum.map(fn key_list ->
      key = key_list |> Enum.join("_") |> String.to_atom()
      {obj_key, other_keys} = List.pop_at(key_list, 0)

      with {:ok, obj} <- Keyword.fetch(bound_variables, obj_key),
           {:ok, value} <- take_nested_attr(obj, other_keys) do
        {key, value}
      else
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp take_nested_attr(obj, keys) do
    case get_in(obj, Enum.map(keys, &Access.key(&1, nil))) do
      nil -> {:error, :not_found}
      value -> {:ok, value}
    end
  end

  defp maybe_add_result(attrs, attr_keys, result) do
    if Enum.member?(attr_keys, :result) do
      Keyword.put_new(attrs, :result, result)
    else
      attrs
    end
  end

  defp remove_underscores(attrs) do
    Enum.map(attrs, fn {key, value} ->
      key =
        key
        |> Atom.to_string()
        |> String.trim_leading("_")
        |> String.to_existing_atom()

      {key, value}
    end)
  end
end
