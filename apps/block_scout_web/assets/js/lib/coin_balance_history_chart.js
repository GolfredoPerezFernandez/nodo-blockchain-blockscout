import $ from 'jquery'
import { Chart, Filler, LineController, LineElement, PointElement, LinearScale, TimeScale, Title, Tooltip } from 'chart.js'
import 'chartjs-adapter-luxon'
import humps from 'humps'

Chart.defaults.font.family = 'Nunito, "Helvetica Neue", Arial, sans-serif,"Apple Color Emoji", "Segoe UI Emoji", "Segoe UI Symbol"'
Chart.register(Filler, LineController, LineElement, PointElement, LinearScale, TimeScale, Title, Tooltip)

export function createCoinBalanceHistoryChart (el) {
  const $chartContainer = $('[data-chart-container]')
  const $chartLoading = $('[data-chart-loading-message]')
  const $chartError = $('[data-chart-error-message]')
  const dataPath = el.dataset.coin_balance_history_data_path

  $.getJSON(dataPath, { type: 'JSON' })
    .done(data => {
      $chartContainer.show()

      const coinBalanceHistoryData = humps.camelizeKeys(data)
        .map(balance => ({
          x: balance.date,
          y: balance.value
        }))

      let stepSize = 3

      if (data.length > 1) {
        const date1 = new Date(data[data.length - 1].date)
        const date2 = new Date(data[data.length - 2].date)
        // @ts-ignore
        const diff = Math.abs(date1 - date2)
        const periodInDays = diff / (1000 * 60 * 60 * 24)

        stepSize = periodInDays
      }
      return new Chart(el, {
        type: 'line',
        data: {
          datasets: [{
            label: 'coin balance',
            data: coinBalanceHistoryData,
            // @ts-ignore
            lineTension: 0,
            cubicInterpolationMode: 'monotone',
            fill: true
          }]
        },
        plugins: {
          // @ts-ignore
          legend: {
            display: false
          }
        },
        interaction: {
          intersect: false,
          mode: 'index'
        },
        options: {
          scales: {
            x: {
              // @ts-ignore
              type: 'time',
              time: {
                unit: 'day',
                tooltipFormat: 'DD',
                // @ts-ignore
                stepSize
              }
            },
            y: {
              // @ts-ignore
              type: 'linear',
              ticks: {
                // @ts-ignore
                beginAtZero: true
              },
              title: {
                display: true,
                // @ts-ignore
                labelString: window.localized.Ether
              }
            }
          }
        }
      })
    })
    .fail(() => {
      $chartError.show()
    })
    .always(() => {
      $chartLoading.hide()
    })
}
