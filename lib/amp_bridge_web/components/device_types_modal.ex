defmodule AmpBridgeWeb.DeviceTypesModal do
  use Phoenix.Component

  @doc """
  Renders a modal that displays device types information in a table format.
  Uses Alpine.js for state management.
  """
  attr(:id, :string, default: "device-types-modal")
  attr(:show, :boolean, required: true)
  attr(:myself, :any, required: true)

  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      class="fixed inset-0 z-50 overflow-y-auto"
      aria-labelledby="modal-title"
      role="dialog"
      aria-modal="true"
      style={if @show, do: "", else: "display: none;"}
    >
      <!-- Background overlay -->
      <div class="flex items-end justify-center min-h-screen pt-4 px-4 pb-20 text-center sm:block sm:p-0">
        <div
          class="fixed inset-0 bg-neutral-500 bg-opacity-75 transition-opacity"
          aria-hidden="true"
          phx-click="close_device_types_modal"
          phx-target={@myself}
        ></div>

        <!-- Modal panel -->
        <div class="inline-block align-bottom bg-neutral-800 rounded-lg text-left overflow-hidden shadow-xl transform transition-all sm:my-8 sm:align-middle sm:max-w-4xl sm:w-full border border-neutral-600">
          <div class="bg-neutral-800 px-4 pt-5 pb-4 sm:p-6 sm:pb-4">
            <div class="sm:flex sm:items-start">
              <div class="mx-auto flex-shrink-0 flex items-center justify-center h-12 w-12 rounded-full bg-blue-900 sm:mx-0 sm:h-10 sm:w-10">
                <svg class="h-6 w-6 text-blue-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
                </svg>
              </div>
              <div class="mt-3 text-center sm:mt-0 sm:ml-4 sm:text-left w-full">
                <h3 class="text-lg leading-6 font-medium text-neutral-100" id="modal-title">
                  Device Types
                </h3>
                <div class="mt-2">
                  <p class="text-sm text-neutral-400">
                    Understanding the different types of audio devices and their capabilities helps you choose the right configuration for your system.
                  </p>
                </div>
              </div>
            </div>
          </div>

          <!-- Device Types Table -->
          <div class="bg-neutral-700 px-4 py-3 sm:px-6">
            <div class="overflow-x-auto">
              <table class="min-w-full divide-y divide-neutral-600">
                <thead class="bg-neutral-600">
                  <tr>
                    <th class="px-6 py-3 text-left text-xs font-medium text-neutral-300 uppercase tracking-wider">
                      Device Type
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-neutral-300 uppercase tracking-wider">
                      Amplification
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-neutral-300 uppercase tracking-wider">
                      Matrix Routing
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-neutral-300 uppercase tracking-wider">
                      Example Products
                    </th>
                  </tr>
                </thead>
                <tbody class="bg-neutral-800 divide-y divide-neutral-600">
                  <tr>
                    <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-neutral-100">
                      Matrix Amplifier
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-neutral-400">
                      Yes
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-neutral-400">
                      Yes
                    </td>
                    <td class="px-6 py-4 text-sm text-neutral-400">
                      Russound SMZ8, Soundavo WS66i
                    </td>
                  </tr>
                  <tr>
                    <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-neutral-100">
                      Multi-Zone Amplifier
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-neutral-400">
                      Yes
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-neutral-400">
                      Limited
                    </td>
                    <td class="px-6 py-4 text-sm text-neutral-400">
                      Juke Audio Juke 6, Russound MCA-66
                    </td>
                  </tr>
                  <tr>
                    <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-neutral-100">
                      Matrix Controller
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-neutral-400">
                      No
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-neutral-400">
                      Yes
                    </td>
                    <td class="px-6 py-4 text-sm text-neutral-400">
                      Russound SMZ16-PRE, Optimal Audio Zone Controller
                    </td>
                  </tr>
                  <tr>
                    <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-neutral-100">
                      Multi-Zone Controller
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-neutral-400">
                      No
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-neutral-400">
                      Limited
                    </td>
                    <td class="px-6 py-4 text-sm text-neutral-400">
                      Control4 controllers, Russound USRC
                    </td>
                  </tr>
                  <tr>
                    <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-neutral-100">
                      Smart Home Controller
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-neutral-400">
                      Sometimes
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-neutral-400">
                      Varies
                    </td>
                    <td class="px-6 py-4 text-sm text-neutral-400">
                      Control4, Russound XTS7 touchscreen
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>

          <!-- Modal footer -->
          <div class="bg-neutral-700 px-4 py-3 sm:px-6 sm:flex sm:flex-row-reverse">
            <button
              type="button"
              class="w-full inline-flex justify-center rounded-md border border-transparent shadow-sm px-4 py-2 bg-blue-600 text-base font-medium text-white hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 sm:ml-3 sm:w-auto sm:text-sm"
              phx-click="close_device_types_modal"
              phx-target={@myself}
            >
              Got it
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
