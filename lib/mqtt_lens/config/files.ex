defmodule MqttLens.Config.Files do
  @moduledoc """
  File reads for `MqttLens.Config`. Sobelow ignores this module only. It holds
  no other logic. All paths come from operator config, never from a request.
  """

  @doc "Read a file. Return `{:ok, binary}` or `{:error, reason}`."
  @spec read(Path.t()) :: {:ok, binary()} | {:error, File.posix()}
  def read(path), do: File.read(path)

  @doc "Read the file `name` in the directory `dir`."
  @spec read_in(Path.t(), Path.t()) :: {:ok, binary()} | {:error, File.posix()}
  def read_in(dir, name), do: File.read(Path.join(dir, name))

  @doc "Return true when `dir` is a directory."
  @spec dir?(Path.t()) :: boolean()
  def dir?(dir), do: File.dir?(dir)
end
