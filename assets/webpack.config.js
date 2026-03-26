const path = require("path");
const MiniCssExtractPlugin = require("mini-css-extract-plugin");

module.exports = (_env, argv) => {
  const devMode = argv.mode === "development";

  return {
    entry: {
      app: "./js/app.js",
    },
    output: {
      filename: "app.js",
      path: path.resolve(__dirname, "../priv/static/js"),
    },
    module: {
      rules: [
        {
          test: /\.js$/,
          exclude: /node_modules/,
          use: "babel-loader",
        },
        {
          test: /\.css$/,
          use: [MiniCssExtractPlugin.loader, "css-loader", "postcss-loader"],
        },
      ],
    },
    plugins: [
      new MiniCssExtractPlugin({
        filename: path.join("..", "css", "app.css"),
      }),
    ],
    devtool: devMode ? "eval-cheap-module-source-map" : "source-map",
    watchOptions: {
      poll: 1000,
      ignored: /node_modules/,
    },
  };
};
