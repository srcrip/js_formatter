defmodule DemoWeb.FormatterDemoLive do
  use DemoWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="space-y-8">
        <header class="space-y-3">
          <p class="text-sm font-semibold uppercase tracking-[0.2em] text-primary">
            JsFormatter integration demo
          </p>
          <h1 class="text-4xl font-bold tracking-tight">
            Colocated JavaScript, checked at the source
          </h1>
          <p class="text-base-content/70">
            This page compiles real colocated TypeScript through Phoenix while the repository's
            formatter delegates its embedded source to Biome or ESLint.
          </p>
        </header>

        <div
          id="formatter-hook-demo"
          phx-hook=".FormatterDemo"
          class="rounded-box border border-base-300 bg-base-100 p-6 shadow-sm"
        >
          <h2 class="text-xl font-semibold">ColocatedHook</h2>
          <p data-status class="mt-2 text-base-content/70">Waiting for the hook to mount…</p>
        </div>

        <formatter-demo-element
          id="formatter-colocated-js-demo"
          class="block rounded-box border border-base-300 bg-base-100 p-6 shadow-sm"
        >
        </formatter-demo-element>
      </section>

      <script
        :type={Phoenix.LiveView.ColocatedHook}
        name=".FormatterDemo"
        extension="ts"
      >
        export default {
          mounted() {
            const status = this.el.querySelector<HTMLElement>("[data-status]");

            if (status) {
              status.textContent = "The colocated TypeScript hook mounted successfully.";
            }
          },
        };
      </script>

      <script
        :type={Phoenix.LiveView.ColocatedJS}
        name="FormatterDemoElement"
        extension="ts"
      >
        export default class FormatterDemoElement extends HTMLElement {
          connectedCallback(): void {
            const heading = document.createElement("h2");
            heading.className = "text-xl font-semibold";
            heading.textContent = "ColocatedJS";

            const description = document.createElement("p");
            description.className = "mt-2 text-base-content/70";
            description.textContent =
              "The custom element class was formatted, linted, bundled, and registered.";

            this.replaceChildren(heading, description);
          }
        }
      </script>

      <script :type={Phoenix.LiveView.ColocatedJS} name="FormatterTsxExample" extension="tsx">
        export default function FormatterTsxExample(name: string) {
          return <span data-name={name}>{name}</span>;
        }
      </script>
    </Layouts.app>
    """
  end
end
